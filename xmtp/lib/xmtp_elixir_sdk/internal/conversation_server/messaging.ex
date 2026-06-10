defmodule XmtpElixirSdk.Internal.ConversationServer.Messaging do
  @moduledoc "Message append, listing, publishing, expiry, and reply/reaction bookkeeping for the conversation server."

  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Internal.ConversationServer.ContentValidation
  alias XmtpElixirSdk.Internal.ConversationServer.Conversations
  alias XmtpElixirSdk.Internal.ConversationServer.Filtering
  alias XmtpElixirSdk.Internal.ConversationServer.MessageConstruction
  alias XmtpElixirSdk.Internal.StatsServer
  alias XmtpElixirSdk.Types.LastReadTime
  alias XmtpElixirSdk.Types.Message

  def get(state, id), do: {:ok, Map.get(state.message_index, id)}

  def list(state, client, conversation_id, opts) do
    next_state = prune_expired(state, client.id, conversation_id)

    case Conversations.fetch(next_state, conversation_id) do
      {:ok, conversation} ->
        messages =
          conversation.messages
          |> Enum.filter(&Filtering.visible_message?(&1, client))
          |> Enum.filter(&Filtering.within_message_window?(&1, opts))
          |> Filtering.filter_messages(opts)
          |> Filtering.sort_messages(opts)
          |> Enum.take(opts.limit)

        {{:ok, messages}, next_state}

      {:error, error} ->
        {{:error, error}, next_state}
    end
  end

  def count(state, client, conversation_id, opts) do
    next_state = prune_expired(state, client.id, conversation_id)

    case Conversations.fetch(next_state, conversation_id) do
      {:ok, conversation} ->
        count =
          conversation.messages
          |> Enum.filter(&Filtering.visible_message?(&1, client))
          |> Enum.filter(&Filtering.countable_message?/1)
          |> Enum.filter(&Filtering.within_message_window?(&1, opts))
          |> Filtering.filter_messages(opts)
          |> length()

        {{:ok, count}, next_state}

      {:error, error} ->
        {{:error, error}, next_state}
    end
  end

  def send(state, client, conversation_id, content, opts) do
    with {:ok, conversation} <- Conversations.fetch(state, conversation_id),
         :ok <- ContentValidation.validate(content) do
      delivery_status =
        if Keyword.get(opts, :is_optimistic, false), do: :unpublished, else: :published

      {next_state, message} = append(state, client, conversation, content, delivery_status)

      StatsServer.bump_api(state.runtime, :send_group_messages)
      {{:ok, message.id}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  def publish(state, client, conversation_id) do
    {next_state, published_ids} =
      case Map.fetch(state.conversations, conversation_id) do
        {:ok, conversation} ->
          messages = Enum.map(conversation.messages, &%{&1 | delivery_status: :published})
          state = put_in(state.conversations[conversation_id].messages, messages)

          state =
            Enum.reduce(messages, state, fn message, acc ->
              put_in(acc.message_index[message.id], message)
            end)

          {state, Enum.map(messages, & &1.id)}

        :error ->
          {state, []}
      end

    StatsServer.bump_api(state.runtime, :publish_commit_log)

    Events.emit(state.runtime, {:messages, client.id}, %Events.MessagePublished{
      conversation_id: conversation_id,
      message_ids: published_ids
    })

    Events.emit(state.runtime, {:messages, conversation_id}, %Events.MessagePublished{
      conversation_id: conversation_id,
      message_ids: published_ids
    })

    next_state
  end

  def last_message(state, client, conversation_id) do
    case Conversations.fetch(state, conversation_id) do
      {:ok, conversation} ->
        last_visible =
          conversation.messages
          |> Enum.filter(&Filtering.visible_message?(&1, client))
          |> List.last()

        {:ok, last_visible}

      {:error, error} ->
        {:error, error}
    end
  end

  def process_streamed(state, client, conversation_id, envelope_bytes) do
    with {:ok, conversation} <- Conversations.fetch(state, conversation_id),
         {:ok, content} <- ContentValidation.decode_streamed(envelope_bytes),
         :ok <- ContentValidation.validate(content) do
      {next_state, message} = append(state, client, conversation, content, :published)
      StatsServer.bump_api(state.runtime, :query_group_messages)
      {{:ok, [message]}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  def append(state, client, conversation, content, delivery_status) do
    message_id = "message-#{state.next_message_id}"
    sent_at_ns = System.system_time(:nanosecond)

    base =
      MessageConstruction.build_message(
        client,
        conversation,
        content,
        message_id,
        sent_at_ns,
        delivery_status
      )

    {message, next_state} = attach_reply_and_reaction_state(state, conversation.id, base)
    next_state = store_message(next_state, conversation.id, message)
    next_state = maybe_update_last_read_times(next_state, conversation.id, message)
    next_state = %{next_state | next_message_id: next_state.next_message_id + 1}

    Events.emit(next_state.runtime, {:messages, client.id}, %Events.MessageCreated{
      message: message
    })

    Events.emit(next_state.runtime, {:messages, conversation.id}, %Events.MessageCreated{
      message: message
    })

    next_state =
      if message.kind == :membership_change do
        Conversations.emit_updated(
          next_state,
          client.id,
          Map.fetch!(next_state.conversations, conversation.id)
        )
      else
        next_state
      end

    {next_state, message}
  end

  def append_system_message(state, client_id, conversation_id, message) do
    next_state = store_message(state, conversation_id, message)

    Events.emit(next_state.runtime, {:messages, client_id}, %Events.MessageCreated{
      message: message
    })

    Events.emit(next_state.runtime, {:messages, conversation_id}, %Events.MessageCreated{
      message: message
    })

    next_state
  end

  def prune_expired(state, client_id, conversation_id) do
    now = System.system_time(:nanosecond)

    cond do
      # No conversation: nothing to prune.
      not Map.has_key?(state.conversations, conversation_id) ->
        state

      # Amortized fast path: the earliest message expiry is still in the
      # future, so no message can be expired and the O(n) scan is skipped.
      now < Map.get(state.next_expiry, conversation_id, 0) ->
        state

      true ->
        do_prune_expired(state, client_id, conversation_id, now)
    end
  end

  defp do_prune_expired(state, client_id, conversation_id, now) do
    conversation = Map.fetch!(state.conversations, conversation_id)

    {expired, kept} =
      Enum.split_with(conversation.messages, &MessageConstruction.expired?(&1, now))

    # Recompute the next expiry checkpoint from the surviving messages so the
    # fast path above can short-circuit subsequent calls.
    state = put_in(state.next_expiry[conversation_id], earliest_expiry(kept))

    if expired == [] do
      state
    else
      updated = %{conversation | messages: kept}
      next_state = put_in(state.conversations[conversation_id], updated)

      next_state =
        Enum.reduce(expired, next_state, fn message, acc ->
          put_in(acc.message_index[message.id], nil)
        end)

      event = %Events.MessageDeleted{
        messages: expired,
        message_ids: Enum.map(expired, & &1.id)
      }

      Events.emit(next_state.runtime, {:deleted_messages, client_id}, event)
      next_state
    end
  end

  # Earliest expiry across messages that can actually expire, used as the prune
  # checkpoint. `0` means "nothing expirable", which disables the fast path so a
  # newly indexed expiring message is still scanned on the next call.
  defp earliest_expiry(messages) do
    messages
    |> Enum.reduce(nil, fn message, acc ->
      case MessageConstruction.effective_expiry(message) do
        nil -> acc
        ns -> min(ns, acc || ns)
      end
    end)
    |> Kernel.||(0)
  end

  defp store_message(state, conversation_id, message) do
    conversation = Map.fetch!(state.conversations, conversation_id)

    updated = %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity_ns: message.sent_at_ns
    }

    state
    |> put_in([Access.key(:conversations), conversation_id], updated)
    |> put_in([Access.key(:message_index), message.id], message)
    |> track_expiry(conversation_id, message)
  end

  # Pull the conversation's prune checkpoint earlier when an expiring message
  # is added, so `prune_expired/3`'s fast path never skips past its expiry.
  defp track_expiry(state, conversation_id, message) do
    case MessageConstruction.effective_expiry(message) do
      nil ->
        state

      ns ->
        update_in(state.next_expiry[conversation_id], fn
          nil -> ns
          0 -> ns
          current -> min(current, ns)
        end)
    end
  end

  defp attach_reply_and_reaction_state(
         state,
         conversation_id,
         %Message{content: %Content.Reaction{reference: reference}} = message
       ) do
    updated_state =
      update_message_relationship(state, conversation_id, reference, fn target ->
        %{target | reactions: target.reactions ++ [message]}
      end)

    {message, updated_state}
  end

  defp attach_reply_and_reaction_state(
         state,
         conversation_id,
         %Message{content: %Content.Reply{reference: reference}} = message
       ) do
    updated_state =
      update_message_relationship(state, conversation_id, reference, fn target ->
        %{target | num_replies: target.num_replies + 1}
      end)

    referenced = Map.get(updated_state.message_index, reference)

    reply_content =
      if referenced, do: %{message.content | in_reply_to: referenced}, else: message.content

    {%{message | content: reply_content, fallback: Content.fallback_for(reply_content)},
     updated_state}
  end

  defp attach_reply_and_reaction_state(state, _conversation_id, message), do: {message, state}

  defp update_message_relationship(state, conversation_id, reference_id, updater) do
    conversation = Map.fetch!(state.conversations, conversation_id)

    case Enum.find_index(conversation.messages, &(&1.id == reference_id)) do
      nil ->
        state

      index ->
        original = Enum.at(conversation.messages, index)
        updated = updater.(original)
        updated_messages = List.replace_at(conversation.messages, index, updated)
        state = put_in(state.conversations[conversation_id].messages, updated_messages)
        put_in(state.message_index[reference_id], updated)
    end
  end

  defp maybe_update_last_read_times(state, conversation_id, %Message{
         content: %Content.ReadReceipt{},
         sender_inbox_id: inbox_id,
         sent_at_ns: sent_at_ns
       }) do
    update_in(state.conversations[conversation_id], fn
      nil ->
        nil

      conversation ->
        updated_last_read_times =
          case Enum.find_index(conversation.last_read_times, &(&1.inbox_id == inbox_id)) do
            nil ->
              conversation.last_read_times ++
                [%LastReadTime{inbox_id: inbox_id, timestamp_ns: sent_at_ns}]

            index ->
              List.update_at(
                conversation.last_read_times,
                index,
                &%{&1 | timestamp_ns: sent_at_ns}
              )
          end

        %{conversation | last_read_times: updated_last_read_times}
    end)
  end

  defp maybe_update_last_read_times(state, _conversation_id, _message), do: state
end

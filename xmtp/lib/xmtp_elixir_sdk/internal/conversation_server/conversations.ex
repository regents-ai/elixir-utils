defmodule XmtpElixirSdk.Internal.ConversationServer.Conversations do
  @moduledoc "Conversation CRUD, lookup, sync, and lifecycle state transitions for the conversation server."

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Internal.ConversationServer.Filtering
  alias XmtpElixirSdk.Internal.ConversationServer.MessageConstruction
  alias XmtpElixirSdk.Internal.ConversationServer.Messaging
  alias XmtpElixirSdk.Internal.ConversationServer.Permissions
  alias XmtpElixirSdk.Internal.StatsServer
  alias XmtpElixirSdk.Types
  alias XmtpElixirSdk.Types.Identifier

  def import_all(state, conversations) do
    Enum.reduce(conversations, state, fn conversation, acc ->
      acc
      |> put_in([Access.key(:conversations), conversation.id], conversation)
      |> index_messages(conversation)
    end)
  end

  def create_dm(state, client, inbox_id, opts) do
    peer_inbox = resolve_inbox_id(state, inbox_id)
    dm_key = MessageConstruction.dm_key(client.inbox_id, peer_inbox)

    next_state =
      if Map.has_key?(state.conversations, dm_key) do
        state
      else
        conversation = MessageConstruction.build_dm_conversation(client, dm_key, peer_inbox, opts)

        state
        |> put_in([Access.key(:conversations), dm_key], conversation)
        |> index_messages(conversation)
        |> emit_created(client.id, conversation)
      end

    StatsServer.bump_api(state.runtime, :send_welcome_messages)
    {{:ok, Map.fetch!(next_state.conversations, dm_key)}, next_state}
  end

  def create_group(state, client, inbox_ids, opts) do
    members = Enum.uniq([client.inbox_id | Enum.map(inbox_ids, &resolve_inbox_id(state, &1))])
    conversation_id = "conversation-#{state.next_conversation_id}"

    conversation =
      MessageConstruction.build_group_conversation(client, conversation_id, members, opts)

    next_state =
      state
      |> put_in([Access.key(:conversations), conversation_id], conversation)
      |> index_messages(conversation)
      |> Map.update!(:next_conversation_id, &(&1 + 1))
      |> emit_created(client.id, conversation)

    StatsServer.bump_api(state.runtime, :send_group_messages)
    {{:ok, conversation}, next_state}
  end

  def get(state, id), do: {:ok, Map.get(state.conversations, id)}

  def list(state, client, opts) do
    conversations =
      state.conversations
      |> Map.values()
      |> Enum.filter(&Filtering.member_of?(&1, client.inbox_id))
      |> Filtering.filter_conversations(opts)
      |> Filtering.sort_conversations(opts)
      |> Enum.take(opts.limit)

    {:ok, conversations}
  end

  def sync(state, client, conversation_id) do
    next_state = Messaging.prune_expired(state, client.id, conversation_id)

    case fetch(next_state, conversation_id) do
      {:ok, conversation} -> {{:ok, conversation}, next_state}
      {:error, error} -> {{:error, error}, next_state}
    end
  end

  def sync_all(state, client, consent_states) do
    conversation_ids =
      state.conversations
      |> Map.values()
      |> Enum.filter(&Filtering.member_of?(&1, client.inbox_id))
      |> Enum.filter(fn conversation ->
        Enum.empty?(consent_states) or conversation.consent_state in consent_states
      end)
      |> Enum.map(& &1.id)

    next_state =
      Enum.reduce(conversation_ids, state, fn conversation_id, acc ->
        Messaging.prune_expired(acc, client.id, conversation_id)
      end)

    StatsServer.bump_api(state.runtime, :query_group_messages)
    synced = length(conversation_ids)
    {{:ok, %Types.SyncResult{synced: synced, eligible: synced}}, next_state}
  end

  def update_field(state, client, conversation_id, field, value) do
    with {:ok, conversation} <- fetch(state, conversation_id),
         :ok <-
           Permissions.ensure(
             client,
             conversation,
             Permissions.action_for_field(field),
             Permissions.metadata_field_for_update(field)
           ) do
      old_value = Map.get(conversation, field)

      updated = %{
        Map.put(conversation, field, value)
        | last_activity_ns: System.system_time(:nanosecond)
      }

      next_state = put_in(state.conversations[conversation_id], updated)

      next_state =
        case Permissions.action_for_field(field) do
          nil ->
            next_state

          _ ->
            Messaging.append_system_message(
              next_state,
              client.id,
              conversation_id,
              MessageConstruction.build_group_update_message_for_field(
                updated,
                client,
                Permissions.metadata_field_for_update(field),
                old_value,
                value
              )
            )
        end

      next_state = emit_updated(next_state, client.id, updated)
      {{:ok, updated}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  def duplicate_dms(state, conversation_id) do
    case fetch(state, conversation_id) do
      {:ok, conversation} ->
        duplicates =
          state.conversations
          |> Map.values()
          |> Enum.filter(
            &(&1.conversation_type == :dm and &1.id != conversation.id and
                &1.metadata.creator_inbox_id == conversation.metadata.creator_inbox_id)
          )

        {:ok, duplicates}

      {:error, error} ->
        {:error, error}
    end
  end

  def debug_info(state, conversation_id) do
    case fetch(state, conversation_id) do
      {:ok, conversation} ->
        {:ok,
         %Types.ConversationDebugInfo{
           epoch: max(length(conversation.messages), 1),
           maybe_forked: false,
           fork_details: "",
           is_commit_log_forked: nil,
           local_commit_log: "local:#{conversation.id}",
           remote_commit_log: "remote:#{conversation.id}",
           cursor: [
             %Types.Cursor{originator_id: 1, sequence_id: max(length(conversation.messages), 1)}
           ]
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  def fetch(state, conversation_id) do
    case Map.fetch(state.conversations, conversation_id) do
      {:ok, conversation} ->
        {:ok, conversation}

      :error ->
        {:error, Error.not_found("conversation not found", %{conversation_id: conversation_id})}
    end
  end

  def fetch_field(state, conversation_id, field) do
    case fetch(state, conversation_id) do
      {:ok, conversation} -> {:ok, Map.get(conversation, field)}
      {:error, error} -> {:error, error}
    end
  end

  def emit_created(state, client_id, conversation) do
    Events.emit(state.runtime, {:conversations, client_id}, %Events.ConversationCreated{
      conversation: conversation
    })

    Events.emit(state.runtime, {:conversation, conversation.id}, %Events.ConversationCreated{
      conversation: conversation
    })

    state
  end

  def emit_updated(state, client_id, conversation) do
    Events.emit(state.runtime, {:conversations, client_id}, %Events.ConversationUpdated{
      conversation: conversation
    })

    Events.emit(state.runtime, {:conversation, conversation.id}, %Events.ConversationUpdated{
      conversation: conversation
    })

    state
  end

  defp resolve_inbox_id(_state, %Identifier{} = identifier), do: identifier.identifier
  defp resolve_inbox_id(_state, inbox_id) when is_binary(inbox_id), do: inbox_id

  defp index_messages(state, conversation) do
    Enum.reduce(conversation.messages, state, fn message, acc ->
      put_in(acc.message_index[message.id], message)
    end)
  end
end

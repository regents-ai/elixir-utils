defmodule XmtpElixirSdk.Internal.ConversationServer do
  @moduledoc false

  use GenServer

  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Internal.Names
  alias XmtpElixirSdk.Internal.StatsServer
  alias XmtpElixirSdk.Types

  alias XmtpElixirSdk.Types.{
    Conversation,
    ConversationMetadata,
    GroupMember,
    HmacKey,
    HmacKeyEntry,
    Identifier,
    LastReadTime,
    Message
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    runtime = Keyword.fetch!(opts, :runtime)
    GenServer.start_link(__MODULE__, %{runtime: runtime}, name: name)
  end

  @spec reset!(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom()) :: :ok
  def reset!(runtime), do: GenServer.call(Names.conversation_server(runtime), :reset)

  @spec import_conversations(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom(), [
          Conversation.t()
        ]) ::
          :ok
  def import_conversations(runtime, conversations) do
    GenServer.call(Names.conversation_server(runtime), {:import_conversations, conversations})
  end

  @spec create_dm(XmtpElixirSdk.Client.t(), String.t(), Types.CreateDmOptions.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def create_dm(client, inbox_id, opts) do
    GenServer.call(Names.conversation_server(client), {:create_dm, client, inbox_id, opts})
  end

  @spec create_group(XmtpElixirSdk.Client.t(), [String.t()], Types.CreateGroupOptions.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def create_group(client, inbox_ids, opts) do
    GenServer.call(Names.conversation_server(client), {:create_group, client, inbox_ids, opts})
  end

  @spec get_conversation_by_id(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, Conversation.t() | nil}
  def get_conversation_by_id(client, id) do
    GenServer.call(Names.conversation_server(client), {:get_conversation_by_id, client, id})
  end

  @spec get_message_by_id(XmtpElixirSdk.Client.t(), String.t()) :: {:ok, Message.t() | nil}
  def get_message_by_id(client, id) do
    GenServer.call(Names.conversation_server(client), {:get_message_by_id, client, id})
  end

  @spec list_conversations(XmtpElixirSdk.Client.t(), Types.ListConversationsOptions.t()) ::
          {:ok, [Conversation.t()]}
  def list_conversations(client, opts) do
    GenServer.call(Names.conversation_server(client), {:list_conversations, client, opts})
  end

  @spec member_conversations(XmtpElixirSdk.Client.t()) :: {:ok, [Conversation.t()]}
  def member_conversations(client) do
    list_conversations(client, %Types.ListConversationsOptions{})
  end

  @spec list_messages(XmtpElixirSdk.Client.t(), String.t(), Types.ListMessagesOptions.t()) ::
          {:ok, [Message.t()]} | {:error, Error.t()}
  def list_messages(client, conversation_id, opts) do
    GenServer.call(
      Names.conversation_server(client),
      {:list_messages, client, conversation_id, opts}
    )
  end

  @spec count_messages(XmtpElixirSdk.Client.t(), String.t(), Types.ListMessagesOptions.t()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def count_messages(client, conversation_id, opts) do
    GenServer.call(
      Names.conversation_server(client),
      {:count_messages, client, conversation_id, opts}
    )
  end

  @spec send_message(XmtpElixirSdk.Client.t(), String.t(), term(), keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_message(client, conversation_id, content, opts \\ []) do
    GenServer.call(
      Names.conversation_server(client),
      {:send_message, client, conversation_id, content, opts}
    )
  end

  @spec publish_messages(XmtpElixirSdk.Client.t(), String.t()) :: :ok
  def publish_messages(client, conversation_id) do
    GenServer.call(
      Names.conversation_server(client),
      {:publish_messages, client, conversation_id}
    )
  end

  @spec conversation_members(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, [GroupMember.t()]} | {:error, Error.t()}
  def conversation_members(client, conversation_id) do
    GenServer.call(
      Names.conversation_server(client),
      {:conversation_members, client, conversation_id}
    )
  end

  @spec conversation_last_message(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, Message.t() | nil} | {:error, Error.t()}
  def conversation_last_message(client, conversation_id) do
    GenServer.call(
      Names.conversation_server(client),
      {:conversation_last_message, client, conversation_id}
    )
  end

  @spec conversation_sync(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def conversation_sync(client, conversation_id) do
    GenServer.call(
      Names.conversation_server(client),
      {:conversation_sync, client, conversation_id}
    )
  end

  @spec sync_conversations(XmtpElixirSdk.Client.t(), [Types.consent_state()]) ::
          {:ok, Types.SyncResult.t()} | {:error, Error.t()}
  def sync_conversations(client, consent_states \\ []) do
    GenServer.call(
      Names.conversation_server(client),
      {:sync_conversations, client, consent_states}
    )
  end

  @spec apply_consent_records(XmtpElixirSdk.Client.t(), [map()]) :: :ok
  def apply_consent_records(client, records) do
    GenServer.call(Names.conversation_server(client), {:apply_consent_records, records})
  end

  @spec consent_for_group(XmtpElixirSdk.Client.t(), String.t()) :: {:ok, Types.consent_state()}
  def consent_for_group(client, group_id) do
    GenServer.call(Names.conversation_server(client), {:consent_for_group, group_id})
  end

  @spec update_conversation_field(XmtpElixirSdk.Client.t(), String.t(), atom(), term()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def update_conversation_field(client, conversation_id, field, value) do
    GenServer.call(
      Names.conversation_server(client),
      {:update_conversation_field, client, conversation_id, field, value}
    )
  end

  @spec update_permission(XmtpElixirSdk.Client.t(), String.t(), atom(), atom(), atom() | nil) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def update_permission(client, conversation_id, update_type, policy, metadata_field) do
    GenServer.call(
      Names.conversation_server(client),
      {:update_permission, client, conversation_id, update_type, policy, metadata_field}
    )
  end

  @spec list_admins(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  def list_admins(client, conversation_id),
    do: GenServer.call(Names.conversation_server(client), {:list_admins, conversation_id})

  @spec list_super_admins(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  def list_super_admins(client, conversation_id),
    do: GenServer.call(Names.conversation_server(client), {:list_super_admins, conversation_id})

  @spec is_admin(XmtpElixirSdk.Client.t(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def is_admin(client, conversation_id, inbox_id),
    do: GenServer.call(Names.conversation_server(client), {:is_admin, conversation_id, inbox_id})

  @spec is_super_admin(XmtpElixirSdk.Client.t(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def is_super_admin(client, conversation_id, inbox_id),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:is_super_admin, conversation_id, inbox_id}
      )

  @spec add_members(XmtpElixirSdk.Client.t(), String.t(), [String.t()]) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def add_members(client, conversation_id, inbox_ids),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:mutate_members, client, conversation_id, inbox_ids, :add}
      )

  @spec remove_members(XmtpElixirSdk.Client.t(), String.t(), [String.t()]) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def remove_members(client, conversation_id, inbox_ids),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:mutate_members, client, conversation_id, inbox_ids, :remove}
      )

  @spec add_admin(XmtpElixirSdk.Client.t(), String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def add_admin(client, conversation_id, inbox_id),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:mutate_admin, client, conversation_id, inbox_id, :add_admin}
      )

  @spec remove_admin(XmtpElixirSdk.Client.t(), String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def remove_admin(client, conversation_id, inbox_id),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:mutate_admin, client, conversation_id, inbox_id, :remove_admin}
      )

  @spec add_super_admin(XmtpElixirSdk.Client.t(), String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def add_super_admin(client, conversation_id, inbox_id),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:mutate_admin, client, conversation_id, inbox_id, :add_super_admin}
      )

  @spec remove_super_admin(XmtpElixirSdk.Client.t(), String.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def remove_super_admin(client, conversation_id, inbox_id),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:mutate_admin, client, conversation_id, inbox_id, :remove_super_admin}
      )

  @spec request_removal(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def request_removal(client, conversation_id),
    do: update_conversation_field(client, conversation_id, :pending_removal, true)

  @spec is_pending_removal(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def is_pending_removal(client, conversation_id),
    do: GenServer.call(Names.conversation_server(client), {:is_pending_removal, conversation_id})

  @spec conversation_disappearing_settings(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, Types.DisappearingSettings.t() | nil} | {:error, Error.t()}
  def conversation_disappearing_settings(client, conversation_id),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:conversation_disappearing_settings, conversation_id}
      )

  @spec update_disappearing_settings(
          XmtpElixirSdk.Client.t(),
          String.t(),
          Types.DisappearingSettings.t()
        ) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def update_disappearing_settings(client, conversation_id, settings),
    do: update_conversation_field(client, conversation_id, :disappearing_settings, settings)

  @spec remove_disappearing_settings(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def remove_disappearing_settings(client, conversation_id),
    do: update_conversation_field(client, conversation_id, :disappearing_settings, nil)

  @spec is_disappearing_enabled(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def is_disappearing_enabled(client, conversation_id),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:is_disappearing_enabled, conversation_id}
      )

  @spec paused_for_version(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def paused_for_version(client, conversation_id),
    do: GenServer.call(Names.conversation_server(client), {:paused_for_version, conversation_id})

  @spec hmac_keys(XmtpElixirSdk.Client.t(), String.t() | :all) ::
          {:ok, [Types.HmacKeyEntry.t()]} | {:error, Error.t()}
  def hmac_keys(client, conversation_id_or_all),
    do: GenServer.call(Names.conversation_server(client), {:hmac_keys, conversation_id_or_all})

  @spec last_read_times(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, [LastReadTime.t()]} | {:error, Error.t()}
  def last_read_times(client, conversation_id),
    do: GenServer.call(Names.conversation_server(client), {:last_read_times, conversation_id})

  @spec duplicate_dms(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, [Conversation.t()]} | {:error, Error.t()}
  def duplicate_dms(client, conversation_id),
    do: GenServer.call(Names.conversation_server(client), {:duplicate_dms, conversation_id})

  @spec process_streamed_message(XmtpElixirSdk.Client.t(), String.t(), binary()) ::
          {:ok, [Message.t()]} | {:error, Error.t()}
  def process_streamed_message(client, conversation_id, envelope_bytes) do
    GenServer.call(
      Names.conversation_server(client),
      {:process_streamed_message, client, conversation_id, envelope_bytes}
    )
  end

  @spec conversation_debug_info(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, Types.ConversationDebugInfo.t()} | {:error, Error.t()}
  def conversation_debug_info(client, conversation_id),
    do:
      GenServer.call(
        Names.conversation_server(client),
        {:conversation_debug_info, conversation_id}
      )

  @impl true
  def init(%{runtime: runtime}) do
    {:ok,
     %{
       runtime: runtime,
       conversations: %{},
       dm_index: %{},
       message_index: %{},
       next_conversation_id: 1,
       next_message_id: 1
     }}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok,
     %{
       state
       | conversations: %{},
         dm_index: %{},
         message_index: %{},
         next_conversation_id: 1,
         next_message_id: 1
     }}
  end

  def handle_call({:import_conversations, conversations}, _from, state) do
    next_state =
      Enum.reduce(conversations, state, fn conversation, acc ->
        acc
        |> put_in([Access.key(:conversations), conversation.id], conversation)
        |> index_conversation_messages(conversation)
      end)

    {:reply, :ok, next_state}
  end

  def handle_call({:create_dm, client, inbox_id, opts}, _from, state) do
    peer_inbox = resolve_inbox_id(state, inbox_id)
    dm_key = dm_key(client.inbox_id, peer_inbox)

    next_state =
      if Map.has_key?(state.conversations, dm_key) do
        state
      else
        conversation = build_dm_conversation(client, dm_key, peer_inbox, opts)

        state
        |> put_in([Access.key(:conversations), dm_key], conversation)
        |> index_conversation_messages(conversation)
        |> emit_conversation_created(client.id, conversation)
      end

    StatsServer.bump_api(state.runtime, :send_welcome_messages)
    {:reply, {:ok, Map.fetch!(next_state.conversations, dm_key)}, next_state}
  end

  def handle_call({:create_group, client, inbox_ids, opts}, _from, state) do
    members = Enum.uniq([client.inbox_id | Enum.map(inbox_ids, &resolve_inbox_id(state, &1))])
    conversation_id = "conversation-#{state.next_conversation_id}"
    conversation = build_group_conversation(client, conversation_id, members, opts)

    next_state =
      state
      |> put_in([Access.key(:conversations), conversation_id], conversation)
      |> index_conversation_messages(conversation)
      |> Map.update!(:next_conversation_id, &(&1 + 1))
      |> emit_conversation_created(client.id, conversation)

    StatsServer.bump_api(state.runtime, :send_group_messages)
    {:reply, {:ok, conversation}, next_state}
  end

  def handle_call({:get_conversation_by_id, _client, id}, _from, state) do
    {:reply, {:ok, Map.get(state.conversations, id)}, state}
  end

  def handle_call({:get_message_by_id, _client, id}, _from, state) do
    {:reply, {:ok, Map.get(state.message_index, id)}, state}
  end

  def handle_call({:list_conversations, client, opts}, _from, state) do
    conversations =
      state.conversations
      |> Map.values()
      |> Enum.filter(&member_of?(&1, client.inbox_id))
      |> filter_conversations(opts)
      |> sort_conversations(opts)
      |> Enum.take(opts.limit)

    {:reply, {:ok, conversations}, state}
  end

  def handle_call({:list_messages, client, conversation_id, opts}, _from, state) do
    next_state = prune_expired_messages(state, client.id, conversation_id)

    with {:ok, conversation} <- fetch_conversation(next_state, conversation_id) do
      messages =
        conversation.messages
        |> Enum.filter(&visible_message?(&1, client))
        |> Enum.filter(&within_message_window?(&1, opts))
        |> maybe_filter_messages(opts)
        |> maybe_sort_messages(opts)
        |> Enum.take(opts.limit)

      {:reply, {:ok, messages}, next_state}
    else
      {:error, error} -> {:reply, {:error, error}, next_state}
    end
  end

  def handle_call({:count_messages, client, conversation_id, opts}, _from, state) do
    next_state = prune_expired_messages(state, client.id, conversation_id)

    with {:ok, conversation} <- fetch_conversation(next_state, conversation_id) do
      count =
        conversation.messages
        |> Enum.filter(&visible_message?(&1, client))
        |> Enum.filter(&countable_message?/1)
        |> Enum.filter(&within_message_window?(&1, opts))
        |> maybe_filter_messages(opts)
        |> length()

      {:reply, {:ok, count}, next_state}
    else
      {:error, error} -> {:reply, {:error, error}, next_state}
    end
  end

  def handle_call({:send_message, client, conversation_id, content, opts}, _from, state) do
    with {:ok, conversation} <- fetch_conversation(state, conversation_id),
         :ok <- validate_content(content) do
      delivery_status =
        if Keyword.get(opts, :is_optimistic, false), do: :unpublished, else: :published

      {next_state, message} =
        append_message(state, client, conversation, content, delivery_status)

      StatsServer.bump_api(state.runtime, :send_group_messages)
      {:reply, {:ok, message.id}, next_state}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:publish_messages, client, conversation_id}, _from, state) do
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

    {:reply, :ok, next_state}
  end

  def handle_call({:conversation_members, _client, conversation_id}, _from, state) do
    case fetch_conversation(state, conversation_id) do
      {:ok, conversation} -> {:reply, {:ok, conversation.members}, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:conversation_last_message, client, conversation_id}, _from, state) do
    with {:ok, conversation} <- fetch_conversation(state, conversation_id) do
      last_visible =
        conversation.messages |> Enum.filter(&visible_message?(&1, client)) |> List.last()

      {:reply, {:ok, last_visible}, state}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:conversation_sync, client, conversation_id}, _from, state) do
    next_state = prune_expired_messages(state, client.id, conversation_id)

    case fetch_conversation(next_state, conversation_id) do
      {:ok, conversation} -> {:reply, {:ok, conversation}, next_state}
      {:error, error} -> {:reply, {:error, error}, next_state}
    end
  end

  def handle_call({:sync_conversations, client, consent_states}, _from, state) do
    conversation_ids =
      state.conversations
      |> Map.values()
      |> Enum.filter(&member_of?(&1, client.inbox_id))
      |> Enum.filter(fn conversation ->
        Enum.empty?(consent_states) or conversation.consent_state in consent_states
      end)
      |> Enum.map(& &1.id)

    next_state =
      Enum.reduce(conversation_ids, state, fn conversation_id, acc ->
        prune_expired_messages(acc, client.id, conversation_id)
      end)

    StatsServer.bump_api(state.runtime, :query_group_messages)
    synced = length(conversation_ids)
    {:reply, {:ok, %Types.SyncResult{synced: synced, eligible: synced}}, next_state}
  end

  def handle_call({:apply_consent_records, records}, _from, state) do
    next_state = Enum.reduce(records, state, &apply_consent_record(&2, &1))
    {:reply, :ok, next_state}
  end

  def handle_call({:consent_for_group, group_id}, _from, state) do
    case fetch_conversation(state, group_id) do
      {:ok, conversation} -> {:reply, {:ok, conversation.consent_state}, state}
      {:error, _} -> {:reply, {:ok, :unknown}, state}
    end
  end

  def handle_call(
        {:update_conversation_field, client, conversation_id, field, value},
        _from,
        state
      ) do
    reply = update_conv_field(state, client, conversation_id, field, value)

    case reply do
      {{:ok, conversation}, next_state} -> {:reply, {:ok, conversation}, next_state}
      {{:error, error}, next_state} -> {:reply, {:error, error}, next_state}
    end
  end

  def handle_call(
        {:update_permission, client, conversation_id, update_type, policy, metadata_field},
        _from,
        state
      ) do
    case fetch_conversation(state, conversation_id) do
      {:ok, conversation} ->
        with :ok <- ensure_permission(client, conversation, :manage_permissions, nil) do
          policies =
            put_permission_policy(
              conversation.permissions.policies,
              update_type,
              policy,
              metadata_field
            )

          updated = %{
            conversation
            | permissions: %{conversation.permissions | policies: policies}
          }

          next_state =
            put_in(state.conversations[conversation_id], updated)
            |> emit_conversation_updated(client.id, updated)

          {:reply, {:ok, updated}, next_state}
        else
          {:error, error} -> {:reply, {:error, error}, state}
        end

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:list_admins, conversation_id}, _from, state) do
    {:reply, fetch_conversation_field(state, conversation_id, :admins), state}
  end

  def handle_call({:list_super_admins, conversation_id}, _from, state) do
    {:reply, fetch_conversation_field(state, conversation_id, :super_admins), state}
  end

  def handle_call({:is_admin, conversation_id, inbox_id}, _from, state) do
    {:reply, boolean_conversation_field(state, conversation_id, :admins, inbox_id), state}
  end

  def handle_call({:is_super_admin, conversation_id, inbox_id}, _from, state) do
    {:reply, boolean_conversation_field(state, conversation_id, :super_admins, inbox_id), state}
  end

  def handle_call({:mutate_members, client, conversation_id, inbox_ids, op}, _from, state) do
    case mutate_members(state, client, conversation_id, inbox_ids, op) do
      {{:ok, conversation}, next_state} -> {:reply, {:ok, conversation}, next_state}
      {{:error, error}, next_state} -> {:reply, {:error, error}, next_state}
    end
  end

  def handle_call({:mutate_admin, client, conversation_id, inbox_id, op}, _from, state) do
    case mutate_admin(state, client, conversation_id, inbox_id, op) do
      {{:ok, conversation}, next_state} -> {:reply, {:ok, conversation}, next_state}
      {{:error, error}, next_state} -> {:reply, {:error, error}, next_state}
    end
  end

  def handle_call({:is_pending_removal, conversation_id}, _from, state) do
    {:reply, fetch_boolean_field(state, conversation_id, :pending_removal), state}
  end

  def handle_call({:conversation_disappearing_settings, conversation_id}, _from, state) do
    {:reply, fetch_conversation_field(state, conversation_id, :disappearing_settings), state}
  end

  def handle_call({:is_disappearing_enabled, conversation_id}, _from, state) do
    reply =
      case fetch_conversation(state, conversation_id) do
        {:ok, conversation} -> {:ok, not is_nil(conversation.disappearing_settings)}
        {:error, error} -> {:error, error}
      end

    {:reply, reply, state}
  end

  def handle_call({:paused_for_version, conversation_id}, _from, state) do
    {:reply, fetch_conversation_field(state, conversation_id, :paused_for_version), state}
  end

  def handle_call({:hmac_keys, :all}, _from, state) do
    {:reply,
     {:ok,
      Enum.flat_map(state.conversations, fn {_id, conversation} -> conversation.hmac_keys end)},
     state}
  end

  def handle_call({:hmac_keys, conversation_id}, _from, state) do
    {:reply, fetch_conversation_field(state, conversation_id, :hmac_keys), state}
  end

  def handle_call({:last_read_times, conversation_id}, _from, state) do
    {:reply, fetch_conversation_field(state, conversation_id, :last_read_times), state}
  end

  def handle_call({:duplicate_dms, conversation_id}, _from, state) do
    case fetch_conversation(state, conversation_id) do
      {:ok, conversation} ->
        duplicates =
          state.conversations
          |> Map.values()
          |> Enum.filter(
            &(&1.conversation_type == :dm and &1.id != conversation.id and
                &1.metadata.creator_inbox_id == conversation.metadata.creator_inbox_id)
          )

        {:reply, {:ok, duplicates}, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(
        {:process_streamed_message, client, conversation_id, envelope_bytes},
        _from,
        state
      ) do
    with {:ok, conversation} <- fetch_conversation(state, conversation_id),
         {:ok, content} <- decode_streamed_content(envelope_bytes),
         :ok <- validate_content(content) do
      {next_state, message} = append_message(state, client, conversation, content, :published)
      StatsServer.bump_api(state.runtime, :query_group_messages)
      {:reply, {:ok, [message]}, next_state}
    else
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:conversation_debug_info, conversation_id}, _from, state) do
    case fetch_conversation(state, conversation_id) do
      {:ok, conversation} ->
        {:reply,
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
          }}, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  defp fetch_conversation(state, conversation_id) do
    case Map.fetch(state.conversations, conversation_id) do
      {:ok, conversation} ->
        {:ok, conversation}

      :error ->
        {:error, Error.not_found("conversation not found", %{conversation_id: conversation_id})}
    end
  end

  defp fetch_conversation_field(state, conversation_id, field) do
    case fetch_conversation(state, conversation_id) do
      {:ok, conversation} -> {:ok, Map.get(conversation, field)}
      {:error, error} -> {:error, error}
    end
  end

  defp fetch_boolean_field(state, conversation_id, field) do
    case fetch_conversation(state, conversation_id) do
      {:ok, conversation} -> {:ok, Map.get(conversation, field)}
      {:error, error} -> {:error, error}
    end
  end

  defp boolean_conversation_field(state, conversation_id, field, value) do
    case fetch_conversation(state, conversation_id) do
      {:ok, conversation} -> {:ok, value in Map.get(conversation, field)}
      {:error, error} -> {:error, error}
    end
  end

  defp emit_conversation_created(state, client_id, conversation) do
    Events.emit(state.runtime, {:conversations, client_id}, %Events.ConversationCreated{
      conversation: conversation
    })

    Events.emit(state.runtime, {:conversation, conversation.id}, %Events.ConversationCreated{
      conversation: conversation
    })

    state
  end

  defp emit_conversation_updated(state, client_id, conversation) do
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

  defp dm_key(a, b), do: [a, b] |> Enum.sort() |> Enum.join(":")

  defp member_of?(conversation, inbox_id),
    do: Enum.any?(conversation.members, &(&1.inbox_id == inbox_id))

  defp maybe_filter_messages(messages, opts) do
    Enum.filter(messages, fn message ->
      delivery_ok? =
        is_nil(opts.delivery_status) or message.delivery_status == opts.delivery_status

      kind_ok? = is_nil(opts.kind) or message.kind == opts.kind

      content_types_ok? =
        Enum.empty?(opts.content_types) or
          content_type_filter_key(message.content_type) in opts.content_types

      delivery_ok? and kind_ok? and content_types_ok?
    end)
  end

  defp within_message_window?(message, opts) do
    after_ok? = opts.sent_after_ns == 0 or message.sent_at_ns >= opts.sent_after_ns
    before_ok? = opts.sent_before_ns == 0 or message.sent_at_ns <= opts.sent_before_ns
    after_ok? and before_ok?
  end

  defp maybe_sort_messages(messages, opts) do
    case opts.direction do
      :descending -> Enum.sort_by(messages, & &1.sent_at_ns, :desc)
      _ -> Enum.sort_by(messages, & &1.sent_at_ns, :asc)
    end
  end

  defp filter_conversations(conversations, opts) do
    Enum.filter(conversations, fn conversation ->
      type_ok? =
        is_nil(opts.conversation_type) or conversation.conversation_type == opts.conversation_type

      consent_ok? =
        Enum.empty?(opts.consent_states) or conversation.consent_state in opts.consent_states

      created_after_ok? =
        opts.created_after_ns == 0 or conversation.created_at_ns > opts.created_after_ns

      created_before_ok? =
        opts.created_before_ns == 0 or conversation.created_at_ns < opts.created_before_ns

      last_activity_after_ok? =
        opts.last_activity_after_ns == 0 or
          conversation.last_activity_ns > opts.last_activity_after_ns

      last_activity_before_ok? =
        opts.last_activity_before_ns == 0 or
          conversation.last_activity_ns < opts.last_activity_before_ns

      type_ok? and consent_ok? and created_after_ok? and created_before_ok? and
        last_activity_after_ok? and last_activity_before_ok?
    end)
  end

  defp sort_conversations(conversations, opts) do
    case opts.order_by do
      :last_activity -> Enum.sort_by(conversations, & &1.last_activity_ns, :desc)
      _ -> Enum.sort_by(conversations, & &1.created_at_ns, :desc)
    end
  end

  defp index_conversation_messages(state, conversation) do
    Enum.reduce(conversation.messages, state, fn message, acc ->
      put_in(acc.message_index[message.id], message)
    end)
  end

  defp append_message(state, client, conversation, content, delivery_status) do
    message_id = "message-#{state.next_message_id}"
    sent_at_ns = System.system_time(:nanosecond)

    base = %Message{
      id: message_id,
      conversation_id: conversation.id,
      sender_inbox_id: client.inbox_id,
      sent_at_ns: sent_at_ns,
      delivery_status: delivery_status,
      kind: message_kind_for_content(content),
      content_type: Content.content_type_id(content),
      content: content,
      fallback: Content.fallback_for(content),
      num_replies: 0,
      reactions: [],
      expires_at_ns: message_expiry_for_conversation(conversation, sent_at_ns, content)
    }

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
        emit_conversation_updated(
          next_state,
          client.id,
          Map.fetch!(next_state.conversations, conversation.id)
        )
      else
        next_state
      end

    {next_state, message}
  end

  defp store_message(state, conversation_id, message) do
    conversation = Map.fetch!(state.conversations, conversation_id)

    updated = %{
      conversation
      | messages: conversation.messages ++ [message],
        last_activity_ns: message.sent_at_ns
    }

    state = put_in(state.conversations[conversation_id], updated)
    put_in(state.message_index[message.id], message)
  end

  defp append_system_message(state, client_id, conversation_id, message) do
    next_state = store_message(state, conversation_id, message)

    Events.emit(next_state.runtime, {:messages, client_id}, %Events.MessageCreated{
      message: message
    })

    Events.emit(next_state.runtime, {:messages, conversation_id}, %Events.MessageCreated{
      message: message
    })

    next_state
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

  defp prune_expired_messages(state, client_id, conversation_id) do
    case Map.fetch(state.conversations, conversation_id) do
      {:ok, conversation} ->
        now = System.system_time(:nanosecond)
        {expired, kept} = Enum.split_with(conversation.messages, &message_expired?(&1, now))

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

      :error ->
        state
    end
  end

  defp message_expired?(%Message{expires_at_ns: nil}, _now_ns), do: false

  defp message_expired?(
         %Message{content_type: %Types.ContentTypeId{type_id: "groupUpdated"}},
         _now_ns
       ), do: false

  defp message_expired?(%Message{expires_at_ns: expires_at_ns}, now_ns),
    do: now_ns >= expires_at_ns

  defp visible_message?(%Message{delivery_status: :unpublished, sender_inbox_id: sender}, client),
    do: sender == client.inbox_id

  defp visible_message?(%Message{}, _client), do: true

  defp countable_message?(%Message{kind: :application}), do: true
  defp countable_message?(%Message{}), do: false

  defp message_kind_for_content(%Content.GroupUpdated{}), do: :membership_change
  defp message_kind_for_content(_), do: :application

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

  defp message_expiry_for_conversation(
         %Conversation{
           disappearing_settings: %Types.DisappearingSettings{from_ns: from_ns, in_ns: in_ns}
         },
         sent_at_ns,
         _content
       )
       when in_ns > 0 do
    if sent_at_ns >= from_ns, do: sent_at_ns + in_ns, else: nil
  end

  defp message_expiry_for_conversation(_conversation, _sent_at_ns, _content), do: nil

  defp apply_consent_record(state, record) do
    entity = Map.get(record, :group_id) || Map.get(record, :entity) || Map.get(record, :inbox_id)
    state_value = Map.get(record, :state, :unknown)

    cond do
      Map.has_key?(state.conversations, entity) ->
        update_in(state.conversations[entity], fn conversation ->
          %{conversation | consent_state: state_value}
        end)

      is_binary(entity) ->
        update_conversation_members_by_inbox(state, entity, fn member ->
          %{member | consent_state: state_value}
        end)

      true ->
        state
    end
  end

  defp update_conversation_members_by_inbox(state, inbox_id, updater) do
    conversations =
      Enum.into(state.conversations, %{}, fn {id, conversation} ->
        updated_members =
          Enum.map(conversation.members, fn member ->
            if member.inbox_id == inbox_id, do: updater.(member), else: member
          end)

        {id, %{conversation | members: updated_members}}
      end)

    %{state | conversations: conversations}
  end

  defp update_conv_field(state, client, conversation_id, field, value) do
    with {:ok, conversation} <- fetch_conversation(state, conversation_id),
         :ok <-
           ensure_permission(
             client,
             conversation,
             permission_action_for_field(field),
             metadata_field_for_update(field)
           ) do
      old_value = Map.get(conversation, field)

      updated = %{
        Map.put(conversation, field, value)
        | last_activity_ns: System.system_time(:nanosecond)
      }

      next_state = put_in(state.conversations[conversation_id], updated)

      next_state =
        case permission_action_for_field(field) do
          nil ->
            next_state

          _ ->
            append_system_message(
              next_state,
              client.id,
              conversation_id,
              build_group_update_message_for_field(updated, client, field, old_value, value)
            )
        end

      next_state = emit_conversation_updated(next_state, client.id, updated)
      {{:ok, updated}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp mutate_members(state, client, conversation_id, inbox_ids, op) do
    with {:ok, conversation} <- fetch_conversation(state, conversation_id),
         :ok <- ensure_permission(client, conversation, op, nil) do
      {members, added_inboxes, removed_inboxes} =
        case op do
          :add ->
            new_members =
              Enum.map(inbox_ids, fn inbox_id ->
                %GroupMember{
                  inbox_id: inbox_id,
                  account_identifiers: [inbox_id],
                  installation_ids: [],
                  permission_level: :member,
                  consent_state: :unknown
                }
              end)

            {Enum.uniq_by(conversation.members ++ new_members, & &1.inbox_id), new_members, []}

          :remove ->
            removed = Enum.filter(conversation.members, &(&1.inbox_id in inbox_ids))
            remaining = Enum.reject(conversation.members, &(&1.inbox_id in inbox_ids))
            {remaining, [], removed}
        end

      updated =
        %{conversation | members: members, last_activity_ns: System.system_time(:nanosecond)}
        |> update_admin_lists_after_member_change()

      next_state = put_in(state.conversations[conversation_id], updated)

      next_state =
        append_system_message(
          next_state,
          client.id,
          conversation_id,
          build_group_update_message(updated, added_inboxes, removed_inboxes, [])
        )

      next_state = emit_conversation_updated(next_state, client.id, updated)
      {{:ok, updated}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp mutate_admin(state, client, conversation_id, inbox_id, op) do
    with {:ok, conversation} <- fetch_conversation(state, conversation_id),
         :ok <- ensure_permission(client, conversation, op, nil) do
      {admins, super_admins} =
        case op do
          :add_admin ->
            {Enum.uniq([inbox_id | conversation.admins]), conversation.super_admins}

          :remove_admin ->
            {Enum.reject(conversation.admins, &(&1 == inbox_id)), conversation.super_admins}

          :add_super_admin ->
            {conversation.admins, Enum.uniq([inbox_id | conversation.super_admins])}

          :remove_super_admin ->
            {conversation.admins, Enum.reject(conversation.super_admins, &(&1 == inbox_id))}
        end

      updated =
        %{
          conversation
          | admins: admins,
            super_admins: super_admins,
            last_activity_ns: System.system_time(:nanosecond)
        }
        |> update_admin_lists_after_member_change()

      next_state =
        put_in(state.conversations[conversation_id], updated)
        |> emit_conversation_updated(client.id, updated)

      {{:ok, updated}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp build_dm_conversation(client, conversation_id, peer_inbox, opts) do
    members = [
      %GroupMember{
        inbox_id: client.inbox_id,
        account_identifiers: [client.identifier.identifier],
        installation_ids: [client.installation_id],
        permission_level: :member,
        consent_state: :allowed
      },
      %GroupMember{
        inbox_id: peer_inbox,
        account_identifiers: [peer_inbox],
        installation_ids: [],
        permission_level: :member,
        consent_state: :unknown
      }
    ]

    initial_message =
      build_group_update_message(
        client,
        conversation_id,
        [
          %GroupMember{
            inbox_id: peer_inbox,
            account_identifiers: [peer_inbox],
            installation_ids: [],
            permission_level: :member,
            consent_state: :unknown
          }
        ],
        [],
        []
      )

    %Conversation{
      id: conversation_id,
      conversation_type: :dm,
      created_at_ns: System.system_time(:nanosecond),
      metadata: %ConversationMetadata{creator_inbox_id: client.inbox_id, conversation_type: :dm},
      added_by_inbox_id: client.inbox_id,
      name: "",
      image_url: "",
      description: "",
      app_data: "",
      permissions: Types.default_permissions(),
      consent_state: :allowed,
      disappearing_settings: Map.get(opts, :disappearing),
      paused_for_version: nil,
      pending_removal: false,
      last_activity_ns: System.system_time(:nanosecond),
      members: members,
      admins: [],
      super_admins: [],
      hmac_keys: [build_hmac_entry(conversation_id)],
      last_read_times: [%LastReadTime{inbox_id: client.inbox_id, timestamp_ns: 0}],
      messages: [initial_message]
    }
  end

  defp build_group_conversation(client, conversation_id, members, opts) do
    group_members =
      Enum.map(members, fn inbox_id ->
        %GroupMember{
          inbox_id: inbox_id,
          account_identifiers: [inbox_id],
          installation_ids: [],
          permission_level: if(inbox_id == client.inbox_id, do: :admin, else: :member),
          consent_state: if(inbox_id == client.inbox_id, do: :allowed, else: :unknown)
        }
      end)

    admins =
      group_members |> Enum.filter(&(&1.permission_level == :admin)) |> Enum.map(& &1.inbox_id)

    super_admins =
      if Enum.any?(group_members, &(&1.inbox_id == client.inbox_id)),
        do: [client.inbox_id],
        else: []

    added_inboxes = Enum.reject(group_members, &(&1.inbox_id == client.inbox_id))

    permissions =
      Types.permission_policies_for_preset(
        Map.get(opts, :permissions, :all_members),
        Map.get(opts, :custom_permission_policy_set)
      )

    initial_message = build_group_update_message(client, conversation_id, added_inboxes, [], [])

    %Conversation{
      id: conversation_id,
      conversation_type: :group,
      created_at_ns: System.system_time(:nanosecond),
      metadata: %ConversationMetadata{
        creator_inbox_id: client.inbox_id,
        conversation_type: :group
      },
      added_by_inbox_id: client.inbox_id,
      name: Map.get(opts, :name, "") || "",
      image_url: Map.get(opts, :image_url, "") || "",
      description: Map.get(opts, :description, "") || "",
      app_data: Map.get(opts, :app_data, "") || "",
      permissions: %Types.Permissions{
        preset: Map.get(opts, :permissions, :all_members),
        policies: permissions
      },
      consent_state: :allowed,
      disappearing_settings: Map.get(opts, :disappearing),
      paused_for_version: nil,
      pending_removal: false,
      last_activity_ns: System.system_time(:nanosecond),
      members: group_members,
      admins: admins,
      super_admins: super_admins,
      hmac_keys: [build_hmac_entry(conversation_id)],
      last_read_times:
        Enum.map(group_members, &%LastReadTime{inbox_id: &1.inbox_id, timestamp_ns: 0}),
      messages: [initial_message]
    }
  end

  defp build_hmac_entry(group_id) do
    %HmacKeyEntry{
      group_id: group_id,
      keys: [%HmacKey{key: :crypto.hash(:sha256, group_id), epoch: 0}]
    }
  end

  defp build_group_update_message(
         %{inbox_id: inbox_id},
         conversation_id,
         added_inboxes,
         removed_inboxes,
         metadata_field_changes
       ) do
    content = %Content.GroupUpdated{
      metadata_field_changes: metadata_field_changes,
      added_inboxes: added_inboxes,
      removed_inboxes: removed_inboxes
    }

    %Message{
      id: "message-#{System.unique_integer([:positive])}",
      conversation_id: conversation_id,
      sender_inbox_id: inbox_id,
      sent_at_ns: System.system_time(:nanosecond),
      delivery_status: :published,
      kind: :membership_change,
      content_type: Content.content_type_id(content),
      content: content,
      fallback: Content.fallback_for(content),
      num_replies: 0,
      reactions: [],
      expires_at_ns: nil
    }
  end

  defp build_group_update_message(
         %Conversation{} = conversation,
         added_inboxes,
         removed_inboxes,
         metadata_field_changes
       ) do
    build_group_update_message(
      %{inbox_id: conversation.added_by_inbox_id || conversation.metadata.creator_inbox_id},
      conversation.id,
      added_inboxes,
      removed_inboxes,
      metadata_field_changes
    )
  end

  defp build_group_update_message_for_field(conversation, client, field, old_value, new_value) do
    change = %Types.MetadataFieldChange{
      field_name: Types.metadata_field_name(metadata_field_for_update(field)),
      old_value: stringify_metadata_value(old_value),
      new_value: stringify_metadata_value(new_value)
    }

    build_group_update_message(client, conversation.id, [], [], [change])
  end

  defp stringify_metadata_value(nil), do: ""
  defp stringify_metadata_value(value) when is_binary(value), do: value
  defp stringify_metadata_value(value), do: inspect(value)

  defp ensure_permission(_client, _conversation, nil, _metadata_field), do: :ok

  defp ensure_permission(client, conversation, action, metadata_field) do
    role =
      cond do
        client.inbox_id in conversation.super_admins -> :super_admin
        client.inbox_id in conversation.admins -> :admin
        true -> :member
      end

    policy =
      case {action, metadata_field} do
        {:add, _} ->
          conversation.permissions.policies.add_member

        {:remove, _} ->
          conversation.permissions.policies.remove_member

        {:add_admin, _} ->
          conversation.permissions.policies.add_admin

        {:remove_admin, _} ->
          conversation.permissions.policies.remove_admin

        {:add_super_admin, _} ->
          conversation.permissions.policies.add_admin

        {:remove_super_admin, _} ->
          conversation.permissions.policies.remove_admin

        {:manage_permissions, _} ->
          :admin_only

        {:update_metadata, :group_name} ->
          conversation.permissions.policies.update_group_name

        {:update_metadata, :description} ->
          conversation.permissions.policies.update_group_description

        {:update_metadata, :image_url} ->
          conversation.permissions.policies.update_group_image_url

        {:update_metadata, :app_data} ->
          conversation.permissions.policies.update_app_data

        {:update_metadata, :message_disappearing} ->
          conversation.permissions.policies.update_message_disappearing

        _ ->
          :allow
      end

    if permission_allows?(policy, role) do
      :ok
    else
      {:error,
       Error.conflict("permission denied", %{
         action: action,
         metadata_field: metadata_field,
         inbox_id: client.inbox_id
       })}
    end
  end

  defp permission_allows?(:allow, _role), do: true
  defp permission_allows?(:deny, _role), do: false
  defp permission_allows?(:admin_only, role), do: role in [:admin, :super_admin]
  defp permission_allows?(:super_admin_only, role), do: role == :super_admin
  defp permission_allows?(_policy, _role), do: true

  defp permission_action_for_field(:name), do: :update_metadata
  defp permission_action_for_field(:description), do: :update_metadata
  defp permission_action_for_field(:image_url), do: :update_metadata
  defp permission_action_for_field(:app_data), do: :update_metadata
  defp permission_action_for_field(:disappearing_settings), do: :update_metadata
  defp permission_action_for_field(:pending_removal), do: nil
  defp permission_action_for_field(_), do: nil

  defp metadata_field_for_update(:name), do: :group_name
  defp metadata_field_for_update(:description), do: :description
  defp metadata_field_for_update(:image_url), do: :image_url
  defp metadata_field_for_update(:app_data), do: :app_data
  defp metadata_field_for_update(:disappearing_settings), do: :message_disappearing
  defp metadata_field_for_update(_), do: nil

  defp put_permission_policy(policies, :add_member, policy, _),
    do: %{policies | add_member: policy}

  defp put_permission_policy(policies, :remove_member, policy, _),
    do: %{policies | remove_member: policy}

  defp put_permission_policy(policies, :add_admin, policy, _), do: %{policies | add_admin: policy}

  defp put_permission_policy(policies, :remove_admin, policy, _),
    do: %{policies | remove_admin: policy}

  defp put_permission_policy(policies, :update_metadata, policy, :group_name),
    do: %{policies | update_group_name: policy}

  defp put_permission_policy(policies, :update_metadata, policy, :description),
    do: %{policies | update_group_description: policy}

  defp put_permission_policy(policies, :update_metadata, policy, :image_url),
    do: %{policies | update_group_image_url: policy}

  defp put_permission_policy(policies, :update_metadata, policy, :message_disappearing),
    do: %{policies | update_message_disappearing: policy}

  defp put_permission_policy(policies, :update_metadata, policy, :app_data),
    do: %{policies | update_app_data: policy}

  defp put_permission_policy(policies, _update_type, _policy, _metadata_field), do: policies

  defp update_admin_lists_after_member_change(%Conversation{} = conversation) do
    member_ids = Enum.map(conversation.members, & &1.inbox_id)
    admins = Enum.filter(conversation.admins, &(&1 in member_ids))
    super_admins = Enum.filter(conversation.super_admins, &(&1 in member_ids))

    members =
      Enum.map(conversation.members, fn member ->
        permission_level =
          cond do
            member.inbox_id in super_admins -> :super_admin
            member.inbox_id in admins -> :admin
            true -> :member
          end

        %{member | permission_level: permission_level}
      end)

    %{conversation | members: members, admins: admins, super_admins: super_admins}
  end

  defp validate_content(%Content.WalletSendCalls{calls: calls}) do
    Enum.reduce_while(calls, :ok, fn call, _acc ->
      case validate_wallet_call(call) do
        :ok -> {:cont, :ok}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp validate_content(_content), do: :ok

  defp validate_wallet_call(%Content.WalletCall{metadata: nil}), do: :ok

  defp validate_wallet_call(%Content.WalletCall{metadata: metadata}) when map_size(metadata) == 0,
    do: :ok

  defp validate_wallet_call(%Content.WalletCall{metadata: metadata}) do
    with :ok <- require_wallet_metadata_field(metadata, :description),
         :ok <- require_wallet_metadata_field(metadata, :transaction_type) do
      :ok
    end
  end

  defp validate_wallet_call(_other),
    do: {:error, Error.invalid_argument("wallet call must use the canonical shape", %{})}

  defp require_wallet_metadata_field(metadata, field) do
    if Map.has_key?(metadata, field) do
      :ok
    else
      {:error,
       Error.invalid_argument("wallet call metadata missing required field", %{field: field})}
    end
  end

  defp decode_streamed_content(envelope_bytes) when is_binary(envelope_bytes) do
    case :erlang.binary_to_term(envelope_bytes, [:safe]) do
      %Message{content: content} -> {:ok, content}
      %Content.Text{} = content -> {:ok, content}
      %Content.Markdown{} = content -> {:ok, content}
      %Content.Reaction{} = content -> {:ok, content}
      %Content.Reply{} = content -> {:ok, content}
      %Content.ReadReceipt{} = content -> {:ok, content}
      %Content.Attachment{} = content -> {:ok, content}
      %Content.RemoteAttachment{} = content -> {:ok, content}
      %Content.GroupUpdated{} = content -> {:ok, content}
      %Content.Actions{} = content -> {:ok, content}
      %Content.Intent{} = content -> {:ok, content}
      %Content.TransactionReference{} = content -> {:ok, content}
      %Content.WalletSendCalls{} = content -> {:ok, content}
      %Content.MultiRemoteAttachment{} = content -> {:ok, content}
      _ -> {:error, Error.invalid_argument("invalid streamed envelope", %{})}
    end
  rescue
    _ -> {:error, Error.invalid_argument("invalid streamed envelope", %{})}
  end

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "text"}), do: :text
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "markdown"}), do: :markdown
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "reaction"}), do: :reaction
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "reply"}), do: :reply
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "readReceipt"}), do: :read_receipt
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "attachment"}), do: :attachment

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "remoteStaticAttachment"}),
    do: :remote_attachment

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "groupUpdated"}), do: :group_updated
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "actions"}), do: :actions
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "intent"}), do: :intent

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "transactionReference"}),
    do: :transaction_reference

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "walletSendCalls"}),
    do: :wallet_send_calls

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "multiRemoteAttachment"}),
    do: :multi_remote_attachment

  defp content_type_filter_key(%Types.ContentTypeId{type_id: type_id}), do: {:unknown, type_id}
end

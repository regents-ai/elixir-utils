defmodule XmtpElixirSdk.Internal.ConversationServer do
  @moduledoc false

  use GenServer

  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Internal.Names
  alias XmtpElixirSdk.Internal.StatsServer
  alias XmtpElixirSdk.Internal.ConversationServer.ContentValidation
  alias XmtpElixirSdk.Internal.ConversationServer.Filtering
  alias XmtpElixirSdk.Internal.ConversationServer.MessageConstruction
  alias XmtpElixirSdk.Internal.ConversationServer.Permissions
  alias XmtpElixirSdk.Types

  alias XmtpElixirSdk.Types.{
    Conversation,
    GroupMember,
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

  @spec apply_consent_records(XmtpElixirSdk.Client.t(), [Types.consent_record()]) :: :ok
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
    dm_key = MessageConstruction.dm_key(client.inbox_id, peer_inbox)

    next_state =
      if Map.has_key?(state.conversations, dm_key) do
        state
      else
        conversation = MessageConstruction.build_dm_conversation(client, dm_key, peer_inbox, opts)

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

    conversation =
      MessageConstruction.build_group_conversation(client, conversation_id, members, opts)

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
      |> Enum.filter(&Filtering.member_of?(&1, client.inbox_id))
      |> Filtering.filter_conversations(opts)
      |> Filtering.sort_conversations(opts)
      |> Enum.take(opts.limit)

    {:reply, {:ok, conversations}, state}
  end

  def handle_call({:list_messages, client, conversation_id, opts}, _from, state) do
    next_state = prune_expired_messages(state, client.id, conversation_id)

    with {:ok, conversation} <- fetch_conversation(next_state, conversation_id) do
      messages =
        conversation.messages
        |> Enum.filter(&Filtering.visible_message?(&1, client))
        |> Enum.filter(&Filtering.within_message_window?(&1, opts))
        |> Filtering.filter_messages(opts)
        |> Filtering.sort_messages(opts)
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
        |> Enum.filter(&Filtering.visible_message?(&1, client))
        |> Enum.filter(&Filtering.countable_message?/1)
        |> Enum.filter(&Filtering.within_message_window?(&1, opts))
        |> Filtering.filter_messages(opts)
        |> length()

      {:reply, {:ok, count}, next_state}
    else
      {:error, error} -> {:reply, {:error, error}, next_state}
    end
  end

  def handle_call({:send_message, client, conversation_id, content, opts}, _from, state) do
    with {:ok, conversation} <- fetch_conversation(state, conversation_id),
         :ok <- ContentValidation.validate(content) do
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
        conversation.messages
        |> Enum.filter(&Filtering.visible_message?(&1, client))
        |> List.last()

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
      |> Enum.filter(&Filtering.member_of?(&1, client.inbox_id))
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
        with {:ok, policy_field} <- Permissions.policy_field(update_type, metadata_field),
             :ok <- Permissions.validate_policy(policy),
             :ok <- Permissions.ensure(client, conversation, :manage_permissions, policy_field) do
          policies =
            Permissions.put_policy(conversation.permissions.policies, policy_field, policy)

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
         {:ok, content} <- ContentValidation.decode_streamed(envelope_bytes),
         :ok <- ContentValidation.validate(content) do
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

  defp index_conversation_messages(state, conversation) do
    Enum.reduce(conversation.messages, state, fn message, acc ->
      put_in(acc.message_index[message.id], message)
    end)
  end

  defp append_message(state, client, conversation, content, delivery_status) do
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

        {expired, kept} =
          Enum.split_with(conversation.messages, &MessageConstruction.expired?(&1, now))

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

  defp apply_consent_record(state, record) do
    entity = Map.get(record, :group_id) || Map.get(record, :entity)
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
            append_system_message(
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

      next_state = emit_conversation_updated(next_state, client.id, updated)
      {{:ok, updated}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp mutate_members(state, client, conversation_id, inbox_ids, op) do
    with {:ok, conversation} <- fetch_conversation(state, conversation_id),
         :ok <- Permissions.ensure(client, conversation, op, nil) do
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
        |> Permissions.update_admin_lists_after_member_change()

      next_state = put_in(state.conversations[conversation_id], updated)

      next_state =
        append_system_message(
          next_state,
          client.id,
          conversation_id,
          MessageConstruction.build_group_update_message(
            updated,
            added_inboxes,
            removed_inboxes,
            []
          )
        )

      next_state = emit_conversation_updated(next_state, client.id, updated)
      {{:ok, updated}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp mutate_admin(state, client, conversation_id, inbox_id, op) do
    with {:ok, conversation} <- fetch_conversation(state, conversation_id),
         :ok <- Permissions.ensure(client, conversation, op, nil) do
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
        |> Permissions.update_admin_lists_after_member_change()

      next_state =
        put_in(state.conversations[conversation_id], updated)
        |> emit_conversation_updated(client.id, updated)

      {{:ok, updated}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end
end

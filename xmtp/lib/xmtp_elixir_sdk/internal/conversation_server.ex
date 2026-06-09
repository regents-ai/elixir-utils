defmodule XmtpElixirSdk.Internal.ConversationServer do
  @moduledoc false

  use GenServer

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Internal.ConversationServer.Consent
  alias XmtpElixirSdk.Internal.ConversationServer.Conversations
  alias XmtpElixirSdk.Internal.ConversationServer.Members
  alias XmtpElixirSdk.Internal.ConversationServer.Messaging
  alias XmtpElixirSdk.Internal.Names
  alias XmtpElixirSdk.Types

  alias XmtpElixirSdk.Types.{
    Conversation,
    GroupMember,
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
    {:reply, :ok, Conversations.import_all(state, conversations)}
  end

  def handle_call({:create_dm, client, inbox_id, opts}, _from, state) do
    {reply, next_state} = Conversations.create_dm(state, client, inbox_id, opts)
    {:reply, reply, next_state}
  end

  def handle_call({:create_group, client, inbox_ids, opts}, _from, state) do
    {reply, next_state} = Conversations.create_group(state, client, inbox_ids, opts)
    {:reply, reply, next_state}
  end

  def handle_call({:get_conversation_by_id, _client, id}, _from, state) do
    {:reply, Conversations.get(state, id), state}
  end

  def handle_call({:get_message_by_id, _client, id}, _from, state) do
    {:reply, Messaging.get(state, id), state}
  end

  def handle_call({:list_conversations, client, opts}, _from, state) do
    {:reply, Conversations.list(state, client, opts), state}
  end

  def handle_call({:list_messages, client, conversation_id, opts}, _from, state) do
    {reply, next_state} = Messaging.list(state, client, conversation_id, opts)
    {:reply, reply, next_state}
  end

  def handle_call({:count_messages, client, conversation_id, opts}, _from, state) do
    {reply, next_state} = Messaging.count(state, client, conversation_id, opts)
    {:reply, reply, next_state}
  end

  def handle_call({:send_message, client, conversation_id, content, opts}, _from, state) do
    {reply, next_state} = Messaging.send(state, client, conversation_id, content, opts)
    {:reply, reply, next_state}
  end

  def handle_call({:publish_messages, client, conversation_id}, _from, state) do
    {:reply, :ok, Messaging.publish(state, client, conversation_id)}
  end

  def handle_call({:conversation_members, _client, conversation_id}, _from, state) do
    {:reply, Members.list(state, conversation_id), state}
  end

  def handle_call({:conversation_last_message, client, conversation_id}, _from, state) do
    {:reply, Messaging.last_message(state, client, conversation_id), state}
  end

  def handle_call({:conversation_sync, client, conversation_id}, _from, state) do
    {reply, next_state} = Conversations.sync(state, client, conversation_id)
    {:reply, reply, next_state}
  end

  def handle_call({:sync_conversations, client, consent_states}, _from, state) do
    {reply, next_state} = Conversations.sync_all(state, client, consent_states)
    {:reply, reply, next_state}
  end

  def handle_call({:apply_consent_records, records}, _from, state) do
    {:reply, :ok, Consent.apply_records(state, records)}
  end

  def handle_call({:consent_for_group, group_id}, _from, state) do
    {:reply, Consent.for_group(state, group_id), state}
  end

  def handle_call(
        {:update_conversation_field, client, conversation_id, field, value},
        _from,
        state
      ) do
    {reply, next_state} = Conversations.update_field(state, client, conversation_id, field, value)
    {:reply, reply, next_state}
  end

  def handle_call(
        {:update_permission, client, conversation_id, update_type, policy, metadata_field},
        _from,
        state
      ) do
    {reply, next_state} =
      Members.update_permission(
        state,
        client,
        conversation_id,
        update_type,
        policy,
        metadata_field
      )

    {:reply, reply, next_state}
  end

  def handle_call({:list_admins, conversation_id}, _from, state) do
    {:reply, Members.admins(state, conversation_id), state}
  end

  def handle_call({:list_super_admins, conversation_id}, _from, state) do
    {:reply, Members.super_admins(state, conversation_id), state}
  end

  def handle_call({:is_admin, conversation_id, inbox_id}, _from, state) do
    {:reply, Members.admin?(state, conversation_id, inbox_id), state}
  end

  def handle_call({:is_super_admin, conversation_id, inbox_id}, _from, state) do
    {:reply, Members.super_admin?(state, conversation_id, inbox_id), state}
  end

  def handle_call({:mutate_members, client, conversation_id, inbox_ids, op}, _from, state) do
    {reply, next_state} = Members.mutate_members(state, client, conversation_id, inbox_ids, op)
    {:reply, reply, next_state}
  end

  def handle_call({:mutate_admin, client, conversation_id, inbox_id, op}, _from, state) do
    {reply, next_state} = Members.mutate_admin(state, client, conversation_id, inbox_id, op)
    {:reply, reply, next_state}
  end

  def handle_call({:is_pending_removal, conversation_id}, _from, state) do
    {:reply, Conversations.fetch_field(state, conversation_id, :pending_removal), state}
  end

  def handle_call({:conversation_disappearing_settings, conversation_id}, _from, state) do
    {:reply, Conversations.fetch_field(state, conversation_id, :disappearing_settings), state}
  end

  def handle_call({:is_disappearing_enabled, conversation_id}, _from, state) do
    reply =
      case Conversations.fetch(state, conversation_id) do
        {:ok, conversation} -> {:ok, not is_nil(conversation.disappearing_settings)}
        {:error, error} -> {:error, error}
      end

    {:reply, reply, state}
  end

  def handle_call({:paused_for_version, conversation_id}, _from, state) do
    {:reply, Conversations.fetch_field(state, conversation_id, :paused_for_version), state}
  end

  def handle_call({:hmac_keys, :all}, _from, state) do
    {:reply,
     {:ok,
      Enum.flat_map(state.conversations, fn {_id, conversation} -> conversation.hmac_keys end)},
     state}
  end

  def handle_call({:hmac_keys, conversation_id}, _from, state) do
    {:reply, Conversations.fetch_field(state, conversation_id, :hmac_keys), state}
  end

  def handle_call({:last_read_times, conversation_id}, _from, state) do
    {:reply, Conversations.fetch_field(state, conversation_id, :last_read_times), state}
  end

  def handle_call({:duplicate_dms, conversation_id}, _from, state) do
    {:reply, Conversations.duplicate_dms(state, conversation_id), state}
  end

  def handle_call(
        {:process_streamed_message, client, conversation_id, envelope_bytes},
        _from,
        state
      ) do
    {reply, next_state} =
      Messaging.process_streamed(state, client, conversation_id, envelope_bytes)

    {:reply, reply, next_state}
  end

  def handle_call({:conversation_debug_info, conversation_id}, _from, state) do
    {:reply, Conversations.debug_info(state, conversation_id), state}
  end
end

defmodule Xmtp.RoomServer do
  @moduledoc false

  use GenServer

  import Ecto.Query, warn: false

  alias Xmtp.Log
  alias Xmtp.Manager
  alias Xmtp.MessageLog
  alias Xmtp.Principal
  alias Xmtp.Room
  alias Xmtp.RoomMembership
  alias Xmtp.RoomPanel
  alias Xmtp.Wallet
  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.Conversations
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Groups
  alias XmtpElixirSdk.Internal.ConversationServer
  alias XmtpElixirSdk.Messages
  alias XmtpElixirSdk.Signer
  alias XmtpElixirSdk.Types

  @message_limit 24

  def start_link(opts) do
    definition = Keyword.fetch!(opts, :definition)
    registry = Keyword.fetch!(opts, :registry)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {registry, definition.key}})
  end

  def child_spec(opts) do
    definition = Keyword.fetch!(opts, :definition)

    %{
      id: {__MODULE__, definition.key},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def init(opts) do
    state =
      %{
        manager: Keyword.fetch!(opts, :manager),
        repo: Keyword.fetch!(opts, :repo),
        pubsub: Keyword.fetch!(opts, :pubsub),
        runtime_name: Keyword.fetch!(opts, :runtime_name),
        definition: Keyword.fetch!(opts, :definition),
        definition_loader: Keyword.get(opts, :definition_loader),
        mode: :unavailable,
        unavailable_reason: :room_unavailable,
        relay_client: nil,
        public_room: nil,
        room: nil,
        clients_by_wallet: %{},
        pending_signatures: %{}
      }
      |> restore_state!()

    schedule_presence_tick(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:public_room_panel, principal, _claims}, _from, state) do
    state = refresh_definition(state)
    {:reply, {:ok, build_panel(state, principal)}, state}
  end

  def handle_call({:request_join, principal, claims}, _from, state) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         {:ok, principal} <- require_principal(principal),
         {:ok, wallet_address} <- fetch_wallet_address(principal),
         :ok <- authorize_join(ready_state, principal, claims),
         false <- room_full?(ready_state, principal),
         {:ok, client, next_state} <-
           ensure_join_candidate(ready_state, principal, wallet_address) do
      cond do
        joined?(next_state, wallet_address) ->
          touched_state =
            touch_membership_presence(next_state, principal, wallet_address, client.inbox_id)

          {:reply, {:ok, build_panel(touched_state, principal)}, touched_state}

        client.ready? ->
          {:ok, panel, updated_state} = invite_joined_member(next_state, principal, client)
          {:reply, {:ok, panel}, updated_state}

        true ->
          {:ok, %{signature_request_id: request_id, signature_text: signature_text}} =
            Clients.unsafe_create_inbox_signature_text(client)

          updated_state =
            put_in(next_state.pending_signatures[request_id], %{
              wallet_address: wallet_address,
              action: :join,
              principal: principal
            })

          panel =
            build_panel(
              updated_state,
              principal,
              "Check your wallet to finish joining.",
              request_id
            )

          {:reply,
           {:needs_signature,
            %{
              request_id: request_id,
              signature_text: signature_text,
              wallet_address: wallet_address,
              panel: panel
            }}, updated_state}
      end
    else
      true -> {:reply, {:error, :room_full}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:complete_join_signature, principal, request_id, signature, claims},
        _from,
        state
      ) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         {:ok, principal} <- require_principal(principal),
         {:ok, wallet_address} <- fetch_wallet_address(principal),
         :ok <- authorize_join(ready_state, principal, claims),
         :ok <- validate_pending_signature(ready_state, request_id, wallet_address, :join),
         {:ok, client} <- fetch_cached_client(ready_state, wallet_address),
         identifier = wallet_identifier(wallet_address),
         {:ok, signer} <- Signer.eoa(identifier, signature),
         :ok <- Clients.unsafe_apply_signature_request(client, request_id, signer),
         {:ok, registered_client} <- Clients.register(client),
         false <- room_full?(ready_state, principal) do
      next_state =
        ready_state
        |> put_in([:clients_by_wallet, wallet_address], registered_client)
        |> update_in([:pending_signatures], &Map.delete(&1, request_id))

      {:ok, panel, updated_state} =
        invite_joined_member(next_state, principal, registered_client)

      {:reply, {:ok, panel}, updated_state}
    else
      true -> {:reply, {:error, :room_full}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_public_message, principal, body}, _from, state) do
    state = refresh_definition(state)
    body = normalize_body(body)

    with {:ok, ready_state} <- require_ready(state),
         {:ok, principal} <- require_principal(principal),
         {:ok, wallet_address} <- fetch_wallet_address(principal),
         :ok <- validate_body(body),
         :ok <- require_joined(ready_state, principal, wallet_address),
         {:ok, client, next_state} <-
           ensure_registered_client(ready_state, principal, wallet_address),
         {:ok, room} <- Conversations.get_by_id(client, ready_state.public_room.id),
         {:ok, message_id} <- Messages.send_text(room, body),
         {:ok, message} <- fetch_message(client, message_id) do
      updated_state =
        next_state
        |> persist_streamed_message(message)
        |> touch_membership_presence(principal, wallet_address, client.inbox_id)

      {:reply, {:ok, build_panel(updated_state, principal)}, updated_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:invite_user, actor, target, claims}, _from, state) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         :ok <- authorize_invite(actor),
         {:ok, principal} <- resolve_target_principal(target),
         {:ok, wallet_address} <- fetch_wallet_address(principal),
         :ok <- authorize_join(ready_state, principal, claims),
         false <- room_full?(ready_state, principal),
         {:ok, client, next_state} <-
           ensure_registered_client(ready_state, principal, wallet_address),
         {:ok, panel, updated_state} <- invite_joined_member(next_state, principal, client) do
      {:reply, {:ok, build_panel(updated_state, actor_or_target(actor, principal)) || panel},
       updated_state}
    else
      true -> {:reply, {:error, :room_full}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:kick_user, actor, target}, _from, state) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         :ok <- authorize_kick(ready_state, actor),
         {:ok, target_member} <- resolve_target_member(ready_state, target),
         {:ok, updated_state} <-
           remove_member(ready_state, target_member.wallet_address, target_member.inbox_id) do
      broadcast_refresh!(updated_state)
      {:reply, {:ok, build_panel(updated_state, actor_or_target(actor, nil))}, updated_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:moderator_delete_message, actor, message_id}, _from, state) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         {:ok, moderator_wallet} <- fetch_moderator_wallet(ready_state, actor),
         {:ok, _entry} <- tombstone_room_message(ready_state, message_id, moderator_wallet) do
      broadcast_refresh!(ready_state)
      {:reply, {:ok, build_panel(ready_state, actor_or_target(actor, nil))}, ready_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:bootstrap_room, opts}, _from, state) do
    state = refresh_definition(state)
    reuse? = Keyword.get(opts, :reuse, false)

    case bootstrap_room(state, reuse?) do
      {:ok, room_info} ->
        :ok = XmtpElixirSdk.Runtime.reset!(state.runtime_name)
        next_state = restore_state!(state)
        {:reply, {:ok, room_info}, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:reset_for_test, _from, state) do
    state = refresh_definition(state)
    delete_room_data(state)
    :ok = XmtpElixirSdk.Runtime.reset!(state.runtime_name)
    {:reply, :ok, restore_state!(state)}
  end

  @impl true
  def handle_cast({:heartbeat, principal}, state) do
    state = refresh_definition(state)

    next_state =
      with {:ok, ready_state} <- require_ready(state),
           {:ok, principal} <- require_principal(principal),
           {:ok, wallet_address} <- fetch_wallet_address(principal),
           {:ok, client, updated_state} <-
             ensure_registered_client(ready_state, principal, wallet_address),
           :ok <- require_joined(updated_state, principal, wallet_address) do
        touch_membership_presence(updated_state, principal, wallet_address, client.inbox_id)
      else
        _ -> state
      end

    {:noreply, next_state}
  end

  @impl true
  def handle_info(:presence_tick, state) do
    state = refresh_definition(state)

    next_state =
      case require_ready(state) do
        {:ok, ready_state} -> expire_stale_memberships(ready_state)
        {:error, _} -> state
      end

    schedule_presence_tick(next_state)
    {:noreply, next_state}
  end

  def handle_info({:xmtp, _topic, %Events.MessageCreated{message: message}}, state) do
    state = refresh_definition(state)

    next_state =
      case require_ready(state) do
        {:ok, ready_state} ->
          if message.conversation_id == ready_state.public_room.id do
            persist_streamed_message(ready_state, message)
          else
            ready_state
          end

        {:error, _} ->
          state
      end

    broadcast_refresh!(next_state)
    {:noreply, next_state}
  end

  def handle_info({:xmtp, _topic, %Events.ConversationUpdated{conversation: conversation}}, state) do
    state = refresh_definition(state)

    next_state =
      case require_ready(state) do
        {:ok, ready_state} ->
          if conversation.id == ready_state.public_room.id do
            public_room =
              XmtpElixirSdk.Conversation.from_record(ready_state.relay_client, conversation)

            persist_room_snapshot(%{ready_state | public_room: public_room}, public_room)
          else
            ready_state
          end

        {:error, _} ->
          state
      end

    broadcast_refresh!(next_state)
    {:noreply, next_state}
  end

  def handle_info({:xmtp, _topic, _event}, state) do
    state = refresh_definition(state)
    broadcast_refresh!(state)
    {:noreply, state}
  end

  defp restore_state!(state) do
    case restore_state(state) do
      {:ok, next_state} ->
        next_state

      {:error, :agent_private_key_missing} ->
        unavailable_state(state, :room_unavailable)

      {:error, :room_not_bootstrapped} ->
        unavailable_state(state, :room_unavailable)

      {:error, reason} ->
        raise "XMTP room agent failed to start for #{state.definition.key}: #{inspect(reason)}"
    end
  end

  defp restore_state(state) do
    repo = state.repo

    with {:ok, private_key} <- configured_private_key(state),
         %Room{} = room <- load_room(repo, state.definition.key),
         {:ok, configured_wallet} <- Wallet.wallet_address(private_key),
         true <-
           configured_wallet == Principal.normalize_wallet(room.agent_wallet_address) or
             {:error, :agent_wallet_mismatch},
         :ok <- XmtpElixirSdk.Runtime.reset!(state.runtime_name),
         {:ok, relay_client} <- build_registered_client(state.runtime_name, private_key),
         true <- relay_client.inbox_id == room.agent_inbox_id or {:error, :agent_inbox_mismatch},
         {:ok, runtime_room} <- import_room_snapshot(state, relay_client, room),
         :ok <- subscribe_room(state.runtime_name, runtime_room.id, self()) do
      {:ok,
       %{
         state
         | mode: :ready,
           unavailable_reason: nil,
           relay_client: relay_client,
           public_room: runtime_room,
           room: room,
           clients_by_wallet: %{},
           pending_signatures: %{}
       }}
    else
      nil -> {:error, :room_not_bootstrapped}
      false -> {:error, :agent_wallet_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bootstrap_room(state, reuse?) do
    with {:ok, private_key} <- configured_private_key(state),
         {:ok, agent_wallet} <- Wallet.wallet_address(private_key) do
      case load_room(state.repo, state.definition.key) do
        %Room{} = room when reuse? ->
          {:ok, encode_room_info(room)}

        %Room{} ->
          {:error, :room_already_bootstrapped}

        nil ->
          :ok = XmtpElixirSdk.Runtime.reset!(state.runtime_name)

          with {:ok, relay_client} <- build_registered_client(state.runtime_name, private_key),
               {:ok, room} <-
                 Conversations.create_group_optimistic(
                   relay_client,
                   %Types.CreateGroupOptions{
                     name: state.definition.name,
                     description: state.definition.description,
                     app_data: state.definition.app_data
                   }
                 ),
               {:ok, room_record} <-
                 persist_bootstrapped_room(state, room, agent_wallet, relay_client.inbox_id) do
            {:ok, encode_room_info(room_record)}
          end
      end
    end
  end

  defp encode_room_info(%Room{} = room) do
    %{
      room_key: room.room_key,
      conversation_id: room.conversation_id,
      agent_wallet_address: room.agent_wallet_address,
      agent_inbox_id: room.agent_inbox_id
    }
  end

  defp persist_bootstrapped_room(state, %Conversation{} = room, agent_wallet, agent_inbox_id) do
    attrs = %{
      room_key: state.definition.key,
      conversation_id: room.id,
      agent_wallet_address: agent_wallet,
      agent_inbox_id: agent_inbox_id,
      status: "active",
      capacity: state.definition.capacity,
      room_name: room.name || state.definition.name,
      description: room.description || state.definition.description,
      app_data: room.app_data || state.definition.app_data,
      created_at_ns: room.created_at_ns,
      last_activity_ns: room.last_activity_ns,
      snapshot: room_snapshot(room)
    }

    %Room{}
    |> Room.changeset(attrs)
    |> state.repo.insert()
  end

  defp import_room_snapshot(state, relay_client, %Room{} = room) do
    conversation =
      build_runtime_conversation(relay_client, room, list_joined_memberships(state.repo, room))

    :ok = ConversationServer.import_conversations(state.runtime_name, [conversation])
    Conversations.get_by_id(relay_client, room.conversation_id)
  end

  defp build_runtime_conversation(relay_client, %Room{} = room, memberships) do
    members = [agent_member(relay_client) | Enum.map(memberships, &membership_to_group_member/1)]
    snapshot = room.snapshot || %{}

    metadata = %Types.ConversationMetadata{
      creator_inbox_id: room.agent_inbox_id,
      conversation_type: :group
    }

    %Types.Conversation{
      id: room.conversation_id,
      conversation_type: :group,
      created_at_ns: room.created_at_ns,
      metadata: metadata,
      added_by_inbox_id: room.agent_inbox_id,
      name: room.room_name,
      image_url: Map.get(snapshot, "image_url"),
      description: room.description || "",
      app_data: room.app_data || "",
      permissions: Types.default_permissions(),
      consent_state: :allowed,
      disappearing_settings: nil,
      paused_for_version: nil,
      pending_removal: false,
      last_activity_ns: room.last_activity_ns,
      members: Enum.uniq_by(members, & &1.inbox_id),
      admins: [room.agent_inbox_id],
      super_admins: [room.agent_inbox_id],
      hmac_keys: [],
      last_read_times: [],
      messages: []
    }
  end

  defp agent_member(relay_client) do
    %Types.GroupMember{
      inbox_id: relay_client.inbox_id,
      account_identifiers: [relay_client.identifier.identifier],
      installation_ids: [relay_client.installation_id],
      permission_level: :admin,
      consent_state: :allowed
    }
  end

  defp membership_to_group_member(%RoomMembership{} = membership) do
    %Types.GroupMember{
      inbox_id: membership.inbox_id,
      account_identifiers: [membership.wallet_address],
      installation_ids: [],
      permission_level: :member,
      consent_state: :allowed
    }
  end

  defp build_registered_client(runtime_name, private_key) do
    with {:ok, wallet_address} <- Wallet.wallet_address(private_key),
         identifier = wallet_identifier(wallet_address),
         {:ok, client} <- Clients.build(runtime_name, identifier, env: :dev),
         {:ok, %{signature_request_id: request_id, signature_text: signature_text}} <-
           Clients.unsafe_create_inbox_signature_text(client),
         {:ok, signature} <- Wallet.sign_personal_message(private_key, signature_text),
         {:ok, signer} <- Signer.eoa(identifier, signature),
         :ok <- Clients.unsafe_apply_signature_request(client, request_id, signer),
         {:ok, registered_client} <- Clients.register(client) do
      {:ok, registered_client}
    end
  end

  defp subscribe_room(runtime_name, room_id, pid) do
    :ok = Events.subscribe(runtime_name, {:messages, room_id}, pid)
    :ok = Events.subscribe(runtime_name, {:conversation, room_id}, pid)
  end

  defp build_panel(state, principal, copy_override \\ nil, pending_request_id \\ nil)

  defp build_panel(
         %{mode: :unavailable, definition: definition},
         principal,
         copy_override,
         pending_request_id
       ) do
    connected_wallet = principal && Principal.wallet(principal)

    RoomPanel.new!(%{
      room_key: definition.key,
      xmtp_group_id: nil,
      name: definition.name,
      status: :disabled,
      membership: if(connected_wallet, do: :not_joined, else: :not_connected),
      connected_wallet: connected_wallet,
      can_join: false,
      can_send: false,
      can_moderate: moderator_wallet?(definition, connected_wallet),
      pending_signature_request_id: pending_request_id,
      member_count: 0,
      active_member_count: 0,
      capacity: definition.capacity,
      seats_remaining: definition.capacity,
      presence_ttl_seconds: div(definition.presence_timeout_ms, 1_000),
      last_synced_at: nil,
      messages: [],
      user_copy: RoomPanel.copy(copy_override || "This room is unavailable right now.")
    })
  end

  defp build_panel(
         %{mode: :ready, room: room, definition: definition} = state,
         principal,
         copy_override,
         pending_signature_request_id
       ) do
    connected_wallet = principal && Principal.wallet(principal)

    membership =
      membership(state, principal, connected_wallet, pending_signature_request_id)

    joined? = membership == :joined
    moderator? = moderator_wallet?(definition, connected_wallet)
    capacity = room.capacity
    member_count = human_member_count(state.repo, room)
    active_member_count = active_human_member_count(state.repo, room, definition)
    seats_remaining = max(capacity - member_count, 0)

    pending_request_id =
      pending_signature_request_id || pending_request_id_for_wallet(state, connected_wallet)

    RoomPanel.new!(%{
      room_key: definition.key,
      xmtp_group_id: room.conversation_id,
      name: room.room_name,
      status: :ready,
      membership: membership,
      connected_wallet: connected_wallet,
      can_join: can_join?(membership, principal),
      can_send: joined?,
      can_moderate: moderator?,
      pending_signature_request_id: pending_request_id,
      member_count: member_count,
      active_member_count: active_member_count,
      capacity: capacity,
      seats_remaining: seats_remaining,
      presence_ttl_seconds: div(definition.presence_timeout_ms, 1_000),
      last_synced_at: room.updated_at,
      user_copy:
        RoomPanel.copy(copy_override || default_copy(membership, principal, seats_remaining)),
      messages: list_panel_messages(state, connected_wallet, moderator?)
    })
  end

  defp list_panel_messages(%{repo: repo, room: room}, connected_wallet, moderator?) do
    repo
    |> Log.list_messages(room)
    |> Enum.reject(&membership_change_message?/1)
    |> Enum.take(-@message_limit)
    |> Enum.map(fn message ->
      sender_wallet = Principal.normalize_wallet(message.sender_wallet)
      moderated? = message.website_visibility_state == "moderator_deleted"

      %{
        key: message.xmtp_message_id,
        author: author_label(message.sender_label, sender_wallet, message.sender_inbox_id),
        body: Log.website_body(message),
        stamp: format_stamp(message.sent_at),
        side: if(connected_wallet && sender_wallet == connected_wallet, do: :self, else: :other),
        sender_inbox_id: message.sender_inbox_id,
        sender_wallet: sender_wallet,
        sender_kind: normalize_sender_kind(message.sender_kind),
        website_state: if(moderated?, do: :moderator_deleted, else: :visible),
        can_delete?: moderator? and not moderated?,
        can_kick?: moderator? and sender_wallet != nil and sender_wallet != connected_wallet
      }
    end)
  end

  defp membership_change_message?(%MessageLog{message_snapshot: %{"kind" => :membership_change}}),
    do: true

  defp membership_change_message?(%MessageLog{
         message_snapshot: %{"kind" => "membership_change"}
       }),
       do: true

  defp membership_change_message?(%MessageLog{
         message_snapshot: %{"content_type_id" => "groupUpdated"}
       }),
       do: true

  defp membership_change_message?(%MessageLog{message_snapshot: %{"content_type_id" => type_id}}),
    do: type_id == "groupUpdated"

  defp membership_change_message?(%MessageLog{}), do: false

  defp membership(_state, nil, _wallet_address, _pending_request_id), do: :not_connected

  defp membership(state, principal, wallet_address, pending_request_id) do
    cond do
      joined?(state, wallet_address) ->
        :joined

      is_binary(pending_request_id) or pending_request_id_for_wallet(state, wallet_address) ->
        :pending_signature

      kicked?(state, wallet_address) ->
        :removed

      room_full?(state, principal) ->
        :blocked

      true ->
        :not_joined
    end
  end

  defp can_join?(:not_joined, %Principal{}), do: true
  defp can_join?(:removed, %Principal{}), do: true
  defp can_join?(_, _), do: false

  defp default_copy(:not_connected, nil, _seats_remaining), do: "Sign in to join this room."

  defp default_copy(:not_joined, principal, seats_remaining),
    do:
      "Connected as #{Principal.short(Principal.wallet(principal))}. #{seats_remaining} seats are open."

  defp default_copy(:pending_signature, _principal, _seats_remaining),
    do: "Check your wallet to finish joining."

  defp default_copy(:joined, principal, _seats_remaining),
    do: "Connected as #{Principal.short(Principal.wallet(principal))}. You are in the room."

  defp default_copy(:blocked, _principal, _seats_remaining),
    do: "This room is full right now. You can still read along."

  defp default_copy(:removed, _principal, seats_remaining),
    do:
      "You were removed from the room. Join again later if a seat opens. #{seats_remaining} seats are open."

  defp persist_streamed_message(%{repo: repo, room: room} = state, message) do
    sender_membership = fetch_membership_for_inbox(repo, room, message.sender_inbox_id)

    _ =
      Log.append_message(repo, room, message, %{
        wallet_address: sender_membership && sender_membership.wallet_address,
        kind: sender_membership && sender_membership.principal_kind,
        label: sender_membership && sender_membership.display_name
      })

    updated_room =
      room
      |> Room.changeset(%{last_activity_ns: message.sent_at_ns})
      |> repo.update!()

    %{state | room: updated_room}
  end

  defp fetch_message(client, message_id) do
    case Messages.get_by_id(client, message_id) do
      {:ok, %Types.Message{} = message} -> {:ok, message}
      {:ok, nil} -> {:error, :message_not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp persist_room_snapshot(
         %{repo: repo, room: room} = state,
         %{id: _conversation_id} = conversation
       ) do
    updated_room =
      room
      |> Room.changeset(%{
        room_name: Map.get(conversation, :name),
        description: Map.get(conversation, :description),
        app_data: Map.get(conversation, :app_data),
        last_activity_ns: Map.get(conversation, :last_activity_ns),
        snapshot: room_snapshot(conversation)
      })
      |> repo.update!()

    %{state | room: updated_room, public_room: conversation}
  end

  defp room_snapshot(%{id: _conversation_id} = conversation) do
    %{
      name: Map.get(conversation, :name),
      description: Map.get(conversation, :description),
      app_data: Map.get(conversation, :app_data),
      created_at_ns: Map.get(conversation, :created_at_ns),
      last_activity_ns: Map.get(conversation, :last_activity_ns),
      image_url: Map.get(conversation, :image_url),
      added_by_inbox_id: Map.get(conversation, :added_by_inbox_id)
    }
  end

  defp invite_joined_member(
         %{public_room: public_room, room: room, repo: repo} = state,
         principal,
         client
       ) do
    with {:ok, updated_room} <- Groups.add_members(public_room, [client.inbox_id]),
         {:ok, _membership} <- upsert_membership(repo, room, principal, client.inbox_id, "joined") do
      next_state =
        state
        |> Map.put(:public_room, updated_room)
        |> Map.put(:room, repo.preload(room, :memberships, force: true))
        |> put_in([:clients_by_wallet, Principal.wallet(principal)], client)
        |> touch_membership_presence(principal, Principal.wallet(principal), client.inbox_id)
        |> persist_room_snapshot(updated_room)

      broadcast_refresh!(next_state)
      {:ok, build_panel(next_state, principal), next_state}
    end
  end

  defp remove_member(
         %{public_room: public_room, room: room, repo: repo} = state,
         wallet_address,
         inbox_id
       ) do
    if Enum.any?(public_room.members, &(&1.inbox_id == inbox_id)) do
      with {:ok, updated_room} <- Groups.remove_members(public_room, [inbox_id]),
           {:ok, _membership} <-
             upsert_membership(
               repo,
               room,
               %Principal{wallet_address: wallet_address},
               inbox_id,
               "kicked"
             ) do
        next_state =
          state
          |> Map.put(:public_room, updated_room)
          |> Map.put(:room, repo.preload(room, :memberships, force: true))
          |> persist_room_snapshot(updated_room)

        {:ok, next_state}
      end
    else
      {:error, :member_not_found}
    end
  end

  defp require_joined(state, principal, wallet_address) do
    cond do
      joined?(state, wallet_address) -> :ok
      kicked?(state, wallet_address) -> {:error, :kicked}
      room_full?(state, principal) -> {:error, :room_full}
      true -> {:error, :join_required}
    end
  end

  defp ensure_join_candidate(state, _principal, wallet_address) do
    case Map.fetch(state.clients_by_wallet, wallet_address) do
      {:ok, client} ->
        {:ok, client, state}

      :error ->
        create_fun =
          if existing_membership?(state.repo, state.room, wallet_address) do
            &Clients.create/3
          else
            &Clients.build/3
          end

        with {:ok, client} <-
               create_fun.(state.runtime_name, wallet_identifier(wallet_address), env: :dev) do
          {:ok, client, put_in(state.clients_by_wallet[wallet_address], client)}
        end
    end
  end

  defp ensure_registered_client(state, _principal, wallet_address) do
    case Map.fetch(state.clients_by_wallet, wallet_address) do
      {:ok, %Client{ready?: true} = client} ->
        {:ok, client, state}

      _ ->
        with {:ok, client} <-
               Clients.create(state.runtime_name, wallet_identifier(wallet_address), env: :dev) do
          {:ok, client, put_in(state.clients_by_wallet[wallet_address], client)}
        end
    end
  end

  defp fetch_cached_client(state, wallet_address) do
    case Map.fetch(state.clients_by_wallet, wallet_address) do
      {:ok, client} -> {:ok, client}
      :error -> {:error, :join_required}
    end
  end

  defp fetch_wallet_address(%Principal{} = principal) do
    case Principal.wallet(principal) do
      nil -> {:error, :wallet_required}
      wallet_address -> {:ok, wallet_address}
    end
  end

  defp fetch_wallet_address(_principal), do: {:error, :wallet_required}

  defp authorize_join(%{definition: definition}, %Principal{} = principal, claims) do
    definition.policy_module.allow_join(definition, principal, claims || %{})
  end

  defp fetch_moderator_wallet(%{definition: definition}, actor) do
    with {:ok, principal} <- resolve_actor_principal(actor),
         {:ok, wallet_address} <- fetch_wallet_address(principal),
         true <- moderator_wallet?(definition, wallet_address) do
      {:ok, wallet_address}
    else
      false -> {:error, :moderator_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_invite(:system), do: :ok
  defp authorize_invite(%Principal{}), do: :ok
  defp authorize_invite(_), do: {:error, :wallet_required}

  defp authorize_kick(state, actor) do
    fetch_moderator_wallet(state, actor)
    |> then(fn result -> if match?({:ok, _}, result), do: :ok, else: result end)
  end

  defp resolve_target_principal(%Principal{} = principal), do: {:ok, principal}
  defp resolve_target_principal(_target), do: {:error, :wallet_required}

  defp resolve_target_member(%{repo: repo, room: room}, %Principal{} = principal) do
    wallet_address = Principal.wallet(principal)
    resolve_target_member(%{repo: repo, room: room}, wallet_address)
  end

  defp resolve_target_member(%{repo: repo, room: room}, target_wallet_or_inbox)
       when is_binary(target_wallet_or_inbox) do
    normalized = String.downcase(String.trim(target_wallet_or_inbox))
    by_wallet = repo.get_by(RoomMembership, room_id: room.id, wallet_address: normalized)
    by_inbox = repo.get_by(RoomMembership, room_id: room.id, inbox_id: normalized)

    case by_wallet || by_inbox do
      %RoomMembership{} = membership ->
        {:ok, %{wallet_address: membership.wallet_address, inbox_id: membership.inbox_id}}

      nil ->
        {:error, :member_not_found}
    end
  end

  defp resolve_target_member(_state, _target), do: {:error, :member_not_found}

  defp validate_pending_signature(state, request_id, wallet_address, action) do
    case Map.get(state.pending_signatures, request_id) do
      %{wallet_address: ^wallet_address, action: ^action} -> :ok
      _ -> {:error, :signature_request_missing}
    end
  end

  defp tombstone_room_message(%{repo: repo, room: room}, message_id, moderator_wallet) do
    case Log.tombstone_message(repo, room, message_id, moderator_wallet) do
      {:ok, entry} -> {:ok, entry}
      {:error, :message_not_found} -> {:error, :message_not_found}
      {:error, _changeset} -> {:error, :message_not_found}
    end
  end

  defp room_full?(%{definition: definition, room: room, repo: repo}, %Principal{} = principal) do
    Principal.kind(principal) == :human and human_member_count(repo, room) >= definition.capacity
  end

  defp room_full?(_, _), do: false

  defp human_member_count(repo, %Room{} = room) do
    repo
    |> list_joined_memberships(room)
    |> Enum.count(&(&1.principal_kind == "human"))
  end

  defp active_human_member_count(repo, %Room{} = room, definition) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-div(definition.presence_timeout_ms, 1_000), :second)

    repo
    |> list_joined_memberships(room)
    |> Enum.count(fn membership ->
      membership.principal_kind == "human" and
        not is_nil(membership.last_seen_at) and
        DateTime.compare(membership.last_seen_at, cutoff) == :gt
    end)
  end

  defp joined?(%{repo: repo, room: room}, wallet_address) do
    case repo.get_by(RoomMembership,
           room_id: room.id,
           wallet_address: Principal.normalize_wallet(wallet_address)
         ) do
      %RoomMembership{membership_state: "joined"} -> true
      _ -> false
    end
  end

  defp existing_membership?(repo, %Room{} = room, wallet_address) do
    not is_nil(
      repo.get_by(RoomMembership,
        room_id: room.id,
        wallet_address: Principal.normalize_wallet(wallet_address)
      )
    )
  end

  defp kicked?(%{repo: repo, room: room}, wallet_address) do
    case repo.get_by(RoomMembership,
           room_id: room.id,
           wallet_address: Principal.normalize_wallet(wallet_address)
         ) do
      %RoomMembership{membership_state: "kicked"} -> true
      _ -> false
    end
  end

  defp pending_request_id_for_wallet(_state, nil), do: nil

  defp pending_request_id_for_wallet(state, wallet_address) do
    Enum.find_value(state.pending_signatures, fn {request_id, pending} ->
      if pending.wallet_address == wallet_address, do: request_id, else: nil
    end)
  end

  defp upsert_membership(
         repo,
         %Room{} = room,
         %Principal{} = principal,
         inbox_id,
         membership_state
       ) do
    attrs = %{
      room_id: room.id,
      wallet_address: Principal.wallet(principal),
      inbox_id: inbox_id,
      principal_kind: Atom.to_string(Principal.kind(principal) || :human),
      display_name: Principal.label(principal),
      membership_state: membership_state,
      last_seen_at: DateTime.utc_now(),
      metadata: principal.metadata || %{}
    }

    existing = repo.get_by(RoomMembership, room_id: room.id, wallet_address: attrs.wallet_address)

    case existing do
      nil ->
        %RoomMembership{}
        |> RoomMembership.changeset(attrs)
        |> repo.insert()

      membership ->
        membership
        |> RoomMembership.changeset(attrs)
        |> repo.update()
    end
  end

  defp touch_membership_presence(
         %{repo: repo, room: room} = state,
         principal,
         _wallet_address,
         inbox_id
       ) do
    _ = upsert_membership(repo, room, principal, inbox_id, "joined")
    %{state | room: repo.preload(room, :memberships, force: true)}
  end

  defp expire_stale_memberships(%{repo: repo, room: room, definition: definition} = state) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-div(definition.presence_timeout_ms, 1_000), :second)

    stale_memberships =
      RoomMembership
      |> where([membership], membership.room_id == ^room.id)
      |> where([membership], membership.membership_state == "joined")
      |> where(
        [membership],
        not is_nil(membership.last_seen_at) and membership.last_seen_at <= ^cutoff
      )
      |> repo.all()

    Enum.reduce(stale_memberships, state, fn membership, acc ->
      case remove_member(acc, membership.wallet_address, membership.inbox_id) do
        {:ok, updated_state} ->
          broadcast_refresh!(updated_state)
          updated_state

        {:error, _reason} ->
          acc
      end
    end)
  end

  defp list_joined_memberships(repo, %Room{id: room_id}) do
    RoomMembership
    |> where([membership], membership.room_id == ^room_id)
    |> where([membership], membership.membership_state == "joined")
    |> order_by([membership], asc: membership.inserted_at)
    |> repo.all()
  end

  defp fetch_membership_for_inbox(repo, %Room{} = room, inbox_id) do
    repo.get_by(RoomMembership, room_id: room.id, inbox_id: inbox_id)
  end

  defp author_label(label, _wallet_address, _inbox_id) when is_binary(label) and label != "",
    do: label

  defp author_label(_label, nil, inbox_id), do: Principal.short(inbox_id)
  defp author_label(_label, wallet_address, _inbox_id), do: Principal.short(wallet_address)

  defp format_stamp(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d %H:%M")

  defp normalize_body(body) when is_binary(body), do: String.trim(body)
  defp normalize_body(_body), do: ""

  defp validate_body(""), do: {:error, :message_required}
  defp validate_body(body) when byte_size(body) > 2_000, do: {:error, :message_too_long}
  defp validate_body(_body), do: :ok

  defp wallet_identifier(wallet_address) do
    %Types.Identifier{
      identifier: Principal.normalize_wallet(wallet_address),
      identifier_kind: :ethereum
    }
  end

  defp moderator_wallet?(_definition, nil), do: false

  defp moderator_wallet?(definition, wallet_address) do
    Principal.normalize_wallet(wallet_address) in Enum.map(
      definition.moderator_wallets,
      &Principal.normalize_wallet/1
    )
  end

  defp configured_private_key(%{definition: definition}) do
    definition.agent_private_key
    |> Wallet.normalize_private_key()
  end

  defp schedule_presence_tick(state) do
    Process.send_after(self(), :presence_tick, state.definition.presence_check_interval_ms)
  end

  defp load_room(repo, room_key) do
    Room
    |> repo.get_by(room_key: room_key)
    |> case do
      nil -> nil
      room -> repo.preload(room, [:memberships])
    end
  end

  defp require_ready(%{mode: :ready} = state), do: {:ok, state}
  defp require_ready(_state), do: {:error, :room_unavailable}

  defp require_principal(%Principal{} = principal), do: {:ok, principal}
  defp require_principal(_principal), do: {:error, :wallet_required}

  defp resolve_actor_principal(%Principal{} = principal), do: {:ok, principal}
  defp resolve_actor_principal(:system), do: {:error, :moderator_required}
  defp resolve_actor_principal(_), do: {:error, :wallet_required}

  defp unavailable_state(state, reason) do
    %{
      state
      | mode: :unavailable,
        unavailable_reason: reason,
        relay_client: nil,
        public_room: nil,
        room: nil,
        clients_by_wallet: %{},
        pending_signatures: %{}
    }
  end

  defp actor_or_target(:system, target), do: target
  defp actor_or_target(%Principal{} = actor, _target), do: actor
  defp actor_or_target(_, target), do: target

  defp refresh_definition(%{definition_loader: {:mfa, module, function, args}} = state) do
    case apply(module, function, args) do
      %Xmtp.RoomDefinition{} = definition -> %{state | definition: definition}
      _ -> state
    end
  end

  defp refresh_definition(state), do: state

  defp broadcast_refresh!(state) do
    Phoenix.PubSub.broadcast(
      state.pubsub,
      Manager.topic(state.manager, state.definition.key),
      {:xmtp_public_room, :refresh}
    )
  end

  defp delete_room_data(state) do
    repo = state.repo

    case load_room(repo, state.definition.key) do
      %Room{} = room ->
        repo.delete_all(from(log in MessageLog, where: log.room_id == ^room.id))
        repo.delete_all(from(membership in RoomMembership, where: membership.room_id == ^room.id))
        repo.delete(room)
        :ok

      nil ->
        :ok
    end
  end

  defp normalize_sender_kind("agent"), do: :agent
  defp normalize_sender_kind(_), do: :human
end

defmodule Xmtp.RoomServer.Lifecycle do
  @moduledoc "Restores and bootstraps room state: relay client registration and runtime conversation import."

  require Logger

  alias Xmtp.Principal
  alias Xmtp.Room
  alias Xmtp.RoomMembership
  alias Xmtp.RoomServer.ClientCache
  alias Xmtp.RoomServer.Membership
  alias Xmtp.RoomServer.Mirror
  alias Xmtp.Wallet
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.Conversations
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Internal.ConversationServer
  alias XmtpElixirSdk.Signer
  alias XmtpElixirSdk.Types

  def restore_state(state) do
    case load_room_state(state) do
      {:ok, next_state} ->
        next_state

      {:error, reason} ->
        log_unavailable(state, reason)
        unavailable_state(state, reason)
    end
  end

  def bootstrap_room(state, reuse?) do
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

  defp load_room_state(state) do
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

  defp log_unavailable(state, reason)
       when reason in [:agent_private_key_missing, :room_not_bootstrapped] do
    Logger.info("XMTP room #{state.definition.key} starting unavailable: #{inspect(reason)}")
  end

  defp log_unavailable(state, reason) do
    Logger.warning("XMTP room #{state.definition.key} starting unavailable: #{inspect(reason)}")
  end

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
      snapshot: Mirror.room_snapshot(room)
    }

    %Room{}
    |> Room.changeset(attrs)
    |> state.repo.insert()
  end

  defp import_room_snapshot(state, relay_client, %Room{} = room) do
    conversation =
      build_runtime_conversation(
        relay_client,
        room,
        Membership.list_joined_memberships(state.repo, room)
      )

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
         identifier = ClientCache.wallet_identifier(wallet_address),
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

  defp configured_private_key(%{definition: definition}) do
    definition.agent_private_key
    |> Wallet.normalize_private_key()
  end

  defp load_room(repo, room_key) do
    Room
    |> repo.get_by(room_key: room_key)
    |> case do
      nil -> nil
      room -> repo.preload(room, [:memberships])
    end
  end
end

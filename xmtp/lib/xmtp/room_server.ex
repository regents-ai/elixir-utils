defmodule Xmtp.RoomServer do
  @moduledoc """
  Runtime process for one Regent XMTP room.

  Product apps should call `Xmtp.Rooms` instead of this module. The room server
  owns the live room process, local room mirror updates, membership state,
  pending join signatures, presence heartbeats, and refresh broadcasts for one
  room key. The logic lives in collaborating modules: `Xmtp.RoomServer.Lifecycle`
  (restore/bootstrap), `Xmtp.RoomServer.Membership` (join/authorization/presence),
  `Xmtp.RoomServer.Panel` (presentation), `Xmtp.RoomServer.ClientCache`
  (per-wallet clients), and `Xmtp.RoomServer.Mirror` (local mirror persistence
  and refresh broadcasts).
  """

  use GenServer

  alias Xmtp.Principal
  alias Xmtp.RoomServer.ClientCache
  alias Xmtp.RoomServer.Lifecycle
  alias Xmtp.RoomServer.Membership
  alias Xmtp.RoomServer.Mirror
  alias Xmtp.RoomServer.Panel
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Conversations
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Messages
  alias XmtpElixirSdk.Signer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    definition = Keyword.fetch!(opts, :definition)
    registry = Keyword.fetch!(opts, :registry)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {registry, definition.key}})
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
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
      |> Lifecycle.restore_state()

    schedule_presence_tick(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:public_room_panel, principal, _claims}, _from, state) do
    state = refresh_definition(state)
    {:reply, {:ok, Panel.build(state, principal)}, state}
  end

  def handle_call({:request_join, principal, claims}, _from, state) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         {:ok, principal} <- require_principal(principal),
         {:ok, wallet_address} <- Membership.fetch_wallet_address(principal),
         :ok <- Membership.authorize_join(ready_state, principal, claims),
         false <- Membership.room_full?(ready_state, principal),
         {:ok, client, next_state} <-
           ClientCache.ensure_join_candidate(ready_state, principal, wallet_address) do
      cond do
        Membership.joined?(next_state, wallet_address) ->
          touched_state =
            Membership.touch_membership_presence(
              next_state,
              principal,
              wallet_address,
              client.inbox_id
            )

          {:reply, {:ok, Panel.build(touched_state, principal)}, touched_state}

        client.ready? ->
          {:ok, panel, updated_state} =
            Membership.invite_joined_member(next_state, principal, client)

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
            Panel.build(
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
         {:ok, wallet_address} <- Membership.fetch_wallet_address(principal),
         :ok <- Membership.authorize_join(ready_state, principal, claims),
         :ok <-
           Membership.validate_pending_signature(ready_state, request_id, wallet_address, :join),
         {:ok, client} <- ClientCache.fetch_cached_client(ready_state, wallet_address),
         identifier = ClientCache.wallet_identifier(wallet_address),
         {:ok, signer} <- Signer.eoa(identifier, signature),
         :ok <- Clients.unsafe_apply_signature_request(client, request_id, signer),
         {:ok, registered_client} <- Clients.register(client),
         false <- Membership.room_full?(ready_state, principal) do
      next_state =
        ready_state
        |> put_in([:clients_by_wallet, wallet_address], registered_client)
        |> update_in([:pending_signatures], &Map.delete(&1, request_id))

      {:ok, panel, updated_state} =
        Membership.invite_joined_member(next_state, principal, registered_client)

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
         {:ok, wallet_address} <- Membership.fetch_wallet_address(principal),
         :ok <- validate_body(body),
         :ok <- Membership.require_joined(ready_state, principal, wallet_address),
         {:ok, client, next_state} <-
           ClientCache.ensure_registered_client(ready_state, principal, wallet_address),
         {:ok, room} <- Conversations.get_by_id(client, ready_state.public_room.id),
         {:ok, message_id} <- Messages.send_text(room, body),
         {:ok, message} <- Mirror.fetch_message(client, message_id) do
      updated_state =
        next_state
        |> Mirror.persist_streamed_message(message)
        |> Membership.touch_membership_presence(principal, wallet_address, client.inbox_id)

      {:reply, {:ok, Panel.build(updated_state, principal)}, updated_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:invite_user, actor, target, claims}, _from, state) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         :ok <- Membership.authorize_invite(actor),
         {:ok, principal} <- Membership.resolve_target_principal(target),
         {:ok, wallet_address} <- Membership.fetch_wallet_address(principal),
         :ok <- Membership.authorize_join(ready_state, principal, claims),
         false <- Membership.room_full?(ready_state, principal),
         {:ok, client, next_state} <-
           ClientCache.ensure_registered_client(ready_state, principal, wallet_address),
         {:ok, panel, updated_state} <-
           Membership.invite_joined_member(next_state, principal, client) do
      {:reply, {:ok, Panel.build(updated_state, actor_or_target(actor, principal)) || panel},
       updated_state}
    else
      true -> {:reply, {:error, :room_full}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:add_remote_member, target, claims}, _from, state) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         {:ok, principal} <- Membership.resolve_target_principal(target),
         {:ok, _wallet_address} <- Membership.fetch_wallet_address(principal),
         :ok <- Membership.authorize_join(ready_state, principal, claims),
         false <- Membership.room_full?(ready_state, principal),
         {:ok, inbox_id} <- Membership.resolve_remote_inbox_id(ready_state, principal),
         {:ok, panel, updated_state} <-
           Membership.add_remote_joined_member(ready_state, principal, inbox_id) do
      {:reply, {:ok, panel}, updated_state}
    else
      true -> {:reply, {:error, :room_full}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:kick_user, actor, target}, _from, state) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         :ok <- Membership.authorize_kick(ready_state, actor),
         {:ok, target_member} <- Membership.resolve_target_member(ready_state, target),
         {:ok, updated_state} <-
           Membership.remove_member(
             ready_state,
             target_member.wallet_address,
             target_member.inbox_id
           ) do
      Mirror.broadcast_refresh!(updated_state)
      {:reply, {:ok, Panel.build(updated_state, actor_or_target(actor, nil))}, updated_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:moderator_delete_message, actor, message_id}, _from, state) do
    state = refresh_definition(state)

    with {:ok, ready_state} <- require_ready(state),
         {:ok, moderator_wallet} <- Membership.fetch_moderator_wallet(ready_state, actor),
         {:ok, _entry} <-
           Mirror.tombstone_room_message(ready_state, message_id, moderator_wallet) do
      Mirror.broadcast_refresh!(ready_state)
      {:reply, {:ok, Panel.build(ready_state, actor_or_target(actor, nil))}, ready_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:bootstrap_room, opts}, _from, state) do
    state = refresh_definition(state)
    reuse? = Keyword.get(opts, :reuse, false)

    case Lifecycle.bootstrap_room(state, reuse?) do
      {:ok, room_info} ->
        :ok = XmtpElixirSdk.Runtime.reset!(state.runtime_name)
        next_state = Lifecycle.restore_state(state)
        {:reply, {:ok, room_info}, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:heartbeat, principal}, state) do
    state = refresh_definition(state)

    next_state =
      with {:ok, ready_state} <- require_ready(state),
           {:ok, principal} <- require_principal(principal),
           {:ok, wallet_address} <- Membership.fetch_wallet_address(principal),
           {:ok, client, updated_state} <-
             ClientCache.ensure_registered_client(ready_state, principal, wallet_address),
           :ok <- Membership.require_joined(updated_state, principal, wallet_address) do
        Membership.touch_membership_presence(
          updated_state,
          principal,
          wallet_address,
          client.inbox_id
        )
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
        {:ok, ready_state} -> Membership.expire_stale_memberships(ready_state)
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
            Mirror.persist_streamed_message(ready_state, message)
          else
            ready_state
          end

        {:error, _} ->
          state
      end

    Mirror.broadcast_refresh!(next_state)
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

            Mirror.persist_room_snapshot(%{ready_state | public_room: public_room}, public_room)
          else
            ready_state
          end

        {:error, _} ->
          state
      end

    Mirror.broadcast_refresh!(next_state)
    {:noreply, next_state}
  end

  def handle_info({:xmtp, _topic, _event}, state) do
    state = refresh_definition(state)
    Mirror.broadcast_refresh!(state)
    {:noreply, state}
  end

  defp require_ready(%{mode: :ready} = state), do: {:ok, state}
  defp require_ready(_state), do: {:error, :room_unavailable}

  defp require_principal(%Principal{} = principal), do: {:ok, principal}
  defp require_principal(_principal), do: {:error, :wallet_required}

  defp actor_or_target(:system, target), do: target
  defp actor_or_target(%Principal{} = actor, _target), do: actor
  defp actor_or_target(_, target), do: target

  defp normalize_body(body) when is_binary(body), do: String.trim(body)
  defp normalize_body(_body), do: ""

  defp validate_body(""), do: {:error, :message_required}
  defp validate_body(body) when byte_size(body) > 2_000, do: {:error, :message_too_long}
  defp validate_body(_body), do: :ok

  defp refresh_definition(%{definition_loader: {:mfa, module, function, args}} = state) do
    case apply(module, function, args) do
      %Xmtp.RoomDefinition{} = definition -> %{state | definition: definition}
      _ -> state
    end
  end

  defp refresh_definition(state), do: state

  defp schedule_presence_tick(state) do
    Process.send_after(self(), :presence_tick, state.definition.presence_check_interval_ms)
  end
end

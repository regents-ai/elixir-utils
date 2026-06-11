defmodule Xmtp.RoomServer.Membership do
  @moduledoc "Join authorization, membership state transitions, and presence tracking for a room server."

  import Ecto.Query, warn: false

  alias Xmtp.Principal
  alias Xmtp.Room
  alias Xmtp.RoomMembership
  alias Xmtp.RoomServer.Mirror
  alias Xmtp.RoomServer.Panel
  alias XmtpElixirSdk.Groups

  def fetch_wallet_address(%Principal{} = principal) do
    case Principal.wallet(principal) do
      nil -> {:error, :wallet_required}
      wallet_address -> {:ok, wallet_address}
    end
  end

  def fetch_wallet_address(_principal), do: {:error, :wallet_required}

  def authorize_join(%{definition: definition}, %Principal{} = principal, claims) do
    definition.policy_module.allow_join(definition, principal, claims || %{})
  end

  def fetch_moderator_wallet(%{definition: definition}, actor) do
    with {:ok, principal} <- resolve_actor_principal(actor),
         {:ok, wallet_address} <- fetch_wallet_address(principal),
         true <- moderator_wallet?(definition, wallet_address) do
      {:ok, wallet_address}
    else
      false -> {:error, :moderator_required}
      {:error, reason} -> {:error, reason}
    end
  end

  def authorize_invite(:system), do: :ok
  def authorize_invite(%Principal{}), do: :ok
  def authorize_invite(_), do: {:error, :wallet_required}

  def authorize_kick(state, actor) do
    fetch_moderator_wallet(state, actor)
    |> then(fn result -> if match?({:ok, _}, result), do: :ok, else: result end)
  end

  def resolve_target_principal(%Principal{} = principal), do: {:ok, principal}
  def resolve_target_principal(_target), do: {:error, :wallet_required}

  def resolve_target_member(%{repo: repo, room: room}, %Principal{} = principal) do
    wallet_address = Principal.wallet(principal)
    resolve_target_member(%{repo: repo, room: room}, wallet_address)
  end

  def resolve_target_member(%{repo: repo, room: room}, target_wallet_or_inbox)
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

  def resolve_target_member(_state, _target), do: {:error, :member_not_found}

  def validate_pending_signature(state, request_id, wallet_address, action) do
    case Map.get(state.pending_signatures, request_id) do
      %{wallet_address: ^wallet_address, action: ^action} -> :ok
      _ -> {:error, :signature_request_missing}
    end
  end

  def require_joined(state, principal, wallet_address) do
    cond do
      joined?(state, wallet_address) -> :ok
      kicked?(state, wallet_address) -> {:error, :kicked}
      room_full?(state, principal) -> {:error, :room_full}
      true -> {:error, :join_required}
    end
  end

  def joined?(%{repo: repo, room: room}, wallet_address) do
    case repo.get_by(RoomMembership,
           room_id: room.id,
           wallet_address: Principal.normalize_wallet(wallet_address)
         ) do
      %RoomMembership{membership_state: "joined"} -> true
      _ -> false
    end
  end

  def kicked?(%{repo: repo, room: room}, wallet_address) do
    case repo.get_by(RoomMembership,
           room_id: room.id,
           wallet_address: Principal.normalize_wallet(wallet_address)
         ) do
      %RoomMembership{membership_state: "kicked"} -> true
      _ -> false
    end
  end

  def existing_membership?(repo, %Room{} = room, wallet_address) do
    not is_nil(
      repo.get_by(RoomMembership,
        room_id: room.id,
        wallet_address: Principal.normalize_wallet(wallet_address)
      )
    )
  end

  def room_full?(%{definition: definition, room: room, repo: repo}, %Principal{} = principal) do
    Principal.kind(principal) == :human and human_member_count(repo, room) >= definition.capacity
  end

  def room_full?(_, _), do: false

  def human_member_count(repo, %Room{} = room) do
    repo
    |> list_joined_memberships(room)
    |> Enum.count(&(&1.principal_kind == "human"))
  end

  def active_human_member_count(repo, %Room{} = room, definition) do
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

  def list_joined_memberships(repo, %Room{id: room_id}) do
    RoomMembership
    |> where([membership], membership.room_id == ^room_id)
    |> where([membership], membership.membership_state == "joined")
    |> order_by([membership], asc: membership.inserted_at)
    |> repo.all()
  end

  def fetch_membership_for_inbox(repo, %Room{} = room, inbox_id) do
    repo.get_by(RoomMembership, room_id: room.id, inbox_id: inbox_id)
  end

  def moderator_wallet?(_definition, nil), do: false

  def moderator_wallet?(definition, wallet_address) do
    Principal.normalize_wallet(wallet_address) in Enum.map(
      definition.moderator_wallets,
      &Principal.normalize_wallet/1
    )
  end

  @doc """
  Resolves the inbox id for a principal whose XMTP identity lives outside this
  server (for example an agent running its own client). Uses the principal's
  `inbox_id` when present, otherwise resolves the wallet via the relay client.
  """
  def resolve_remote_inbox_id(_state, %Principal{inbox_id: inbox_id})
      when is_binary(inbox_id) and inbox_id != "" do
    {:ok, inbox_id}
  end

  def resolve_remote_inbox_id(%{relay_client: relay_client}, %Principal{} = principal) do
    with {:ok, wallet_address} <- fetch_wallet_address(principal) do
      case XmtpElixirSdk.Native.inbox_id_for(relay_client, wallet_address) do
        {:ok, inbox_id} when is_binary(inbox_id) and inbox_id != "" -> {:ok, inbox_id}
        {:ok, _missing} -> {:error, :no_xmtp_identity}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Adds a member that owns its XMTP identity remotely: the relay adds the inbox to
  the group and records the membership. No server-side client is created or cached
  for the member; the member sends messages from its own runtime.
  """
  def add_remote_joined_member(
        %{public_room: public_room, room: room, repo: repo} = state,
        principal,
        inbox_id
      ) do
    with {:ok, updated_room} <- Groups.add_members(public_room, [inbox_id]),
         {:ok, _membership} <- upsert_membership(repo, room, principal, inbox_id, "joined") do
      next_state =
        state
        |> Map.put(:public_room, updated_room)
        |> Map.put(:room, repo.preload(room, :memberships, force: true))
        |> touch_membership_presence(principal, Principal.wallet(principal), inbox_id)
        |> Mirror.persist_room_snapshot(updated_room)

      Mirror.broadcast_refresh!(next_state)
      {:ok, Panel.build(next_state, principal), next_state}
    end
  end

  def invite_joined_member(
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
        |> Mirror.persist_room_snapshot(updated_room)

      Mirror.broadcast_refresh!(next_state)
      {:ok, Panel.build(next_state, principal), next_state}
    end
  end

  def remove_member(
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
          |> Mirror.persist_room_snapshot(updated_room)

        {:ok, next_state}
      end
    else
      {:error, :member_not_found}
    end
  end

  def touch_membership_presence(
        %{repo: repo, room: room} = state,
        principal,
        _wallet_address,
        inbox_id
      ) do
    _ = upsert_membership(repo, room, principal, inbox_id, "joined")
    %{state | room: repo.preload(room, :memberships, force: true)}
  end

  def expire_stale_memberships(%{repo: repo, room: room, definition: definition} = state) do
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
          Mirror.broadcast_refresh!(updated_state)
          updated_state

        {:error, _reason} ->
          acc
      end
    end)
  end

  defp resolve_actor_principal(%Principal{} = principal), do: {:ok, principal}
  defp resolve_actor_principal(:system), do: {:error, :moderator_required}
  defp resolve_actor_principal(_), do: {:error, :wallet_required}

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
end

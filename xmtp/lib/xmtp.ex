defmodule Xmtp do
  @moduledoc false

  alias Xmtp.Manager
  alias Xmtp.Principal
  alias Xmtp.RoomPanel

  @type manager :: module()
  @type room_key :: String.t() | atom()
  @type principal :: Principal.t() | map() | nil
  @type panel_result :: {:ok, RoomPanel.t()} | {:error, term()}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts), do: Manager.child_spec(opts)

  @spec topic(manager(), room_key()) :: String.t()
  def topic(manager, room_key), do: Manager.topic(manager, room_key)

  @spec subscribe(manager(), room_key(), pid()) :: :ok | {:error, term()}
  def subscribe(manager, room_key, subscriber \\ self()) do
    Phoenix.PubSub.subscribe(Manager.pubsub(manager), topic(manager, room_key),
      metadata: %{pid: subscriber}
    )
  end

  @spec public_room_panel(manager(), room_key(), principal(), map()) :: panel_result()
  def public_room_panel(manager, room_key, principal \\ nil, claims \\ %{}) do
    call(manager, room_key, {:public_room_panel, Principal.from(principal), claims})
  end

  @spec request_join(manager(), room_key(), principal(), map()) ::
          panel_result() | {:needs_signature, map()}
  def request_join(manager, room_key, principal, claims \\ %{}) do
    call(manager, room_key, {:request_join, Principal.from(principal), claims})
  end

  @spec complete_join_signature(
          manager(),
          room_key(),
          principal(),
          String.t(),
          String.t(),
          map()
        ) :: panel_result()
  def complete_join_signature(manager, room_key, principal, request_id, signature, claims \\ %{}) do
    call(
      manager,
      room_key,
      {:complete_join_signature, Principal.from(principal), request_id, signature, claims}
    )
  end

  @spec send_public_message(manager(), room_key(), principal(), String.t()) :: panel_result()
  def send_public_message(manager, room_key, principal, body) do
    call(manager, room_key, {:send_public_message, Principal.from(principal), body})
  end

  @spec invite_user(manager(), room_key(), principal() | :system, principal(), map()) ::
          panel_result()
  def invite_user(manager, room_key, actor, target, claims \\ %{}) do
    call(
      manager,
      room_key,
      {:invite_user, normalize_actor(actor), normalize_target(target), claims}
    )
  end

  @spec add_remote_member(manager(), room_key(), principal(), map()) :: panel_result()
  def add_remote_member(manager, room_key, target, claims \\ %{}) do
    call(manager, room_key, {:add_remote_member, Principal.from(target), claims})
  end

  @spec kick_user(manager(), room_key(), principal() | :system, principal() | String.t()) ::
          panel_result()
  def kick_user(manager, room_key, actor, target) do
    call(manager, room_key, {:kick_user, normalize_actor(actor), normalize_target(target)})
  end

  @spec moderator_delete_message(manager(), room_key(), principal() | :system, String.t()) ::
          panel_result()
  def moderator_delete_message(manager, room_key, actor, message_id) do
    call(manager, room_key, {:moderator_delete_message, normalize_actor(actor), message_id})
  end

  @spec heartbeat(manager(), room_key(), principal()) :: :ok
  def heartbeat(manager, room_key, principal) do
    GenServer.cast(Manager.via(manager, room_key), {:heartbeat, Principal.from(principal)})
  end

  @spec bootstrap_room!(manager(), room_key(), keyword()) :: {:ok, map()} | {:error, term()}
  def bootstrap_room!(manager, room_key, opts \\ []) do
    call(manager, room_key, {:bootstrap_room, opts}, :timer.seconds(30))
  end

  defp call(manager, room_key, message, timeout \\ 5_000) do
    with :ok <- Manager.ensure_room_started(manager, room_key) do
      GenServer.call(Manager.via(manager, room_key), message, timeout)
    end
  end

  defp normalize_actor(:system), do: :system
  defp normalize_actor(actor), do: Principal.from(actor)

  defp normalize_target(target) when is_binary(target), do: String.trim(target)
  defp normalize_target(target), do: Principal.from(target)
end

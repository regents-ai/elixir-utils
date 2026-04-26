defmodule Xmtp do
  @moduledoc false

  alias Xmtp.Manager
  alias Xmtp.Principal

  def child_spec(opts), do: Manager.child_spec(opts)

  def topic(manager, room_key), do: Manager.topic(manager, room_key)

  def subscribe(manager, room_key, subscriber \\ self()) do
    Phoenix.PubSub.subscribe(Manager.pubsub(manager), topic(manager, room_key),
      metadata: %{pid: subscriber}
    )
  end

  def public_room_panel(manager, room_key, principal \\ nil, claims \\ %{}) do
    call(manager, room_key, {:public_room_panel, Principal.from(principal), claims})
  end

  def request_join(manager, room_key, principal, claims \\ %{}) do
    call(manager, room_key, {:request_join, Principal.from(principal), claims})
  end

  def complete_join_signature(manager, room_key, principal, request_id, signature, claims \\ %{}) do
    call(
      manager,
      room_key,
      {:complete_join_signature, Principal.from(principal), request_id, signature, claims}
    )
  end

  def send_public_message(manager, room_key, principal, body) do
    call(manager, room_key, {:send_public_message, Principal.from(principal), body})
  end

  def invite_user(manager, room_key, actor, target, claims \\ %{}) do
    call(
      manager,
      room_key,
      {:invite_user, normalize_actor(actor), normalize_target(target), claims}
    )
  end

  def kick_user(manager, room_key, actor, target) do
    call(manager, room_key, {:kick_user, normalize_actor(actor), normalize_target(target)})
  end

  def moderator_delete_message(manager, room_key, actor, message_id) do
    call(manager, room_key, {:moderator_delete_message, normalize_actor(actor), message_id})
  end

  def heartbeat(manager, room_key, principal) do
    GenServer.cast(Manager.via(manager, room_key), {:heartbeat, Principal.from(principal)})
  end

  def bootstrap_room!(manager, room_key, opts \\ []) do
    call(manager, room_key, {:bootstrap_room, opts}, :timer.seconds(30))
  end

  def reset_for_test!(manager, room_key) do
    call(manager, room_key, :reset_for_test, :timer.seconds(30))
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

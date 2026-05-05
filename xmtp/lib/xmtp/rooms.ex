defmodule Xmtp.Rooms do
  @moduledoc """
  Canonical room action facade for product apps.
  """

  alias Xmtp.Principal

  @spec panel(module(), String.t(), Principal.t() | map() | nil, map()) ::
          {:ok, Xmtp.RoomPanel.t()} | {:error, term()}
  def panel(manager, room_key, principal \\ nil, claims \\ %{}) do
    Xmtp.public_room_panel(manager, room_key, principal, claims)
  end

  @spec request_join(module(), String.t(), Principal.t() | map(), map()) ::
          {:ok, Xmtp.RoomPanel.t()} | {:needs_signature, map()} | {:error, term()}
  def request_join(manager, room_key, principal, claims \\ %{}) do
    Xmtp.request_join(manager, room_key, principal, claims)
  end

  @spec complete_join_signature(
          module(),
          String.t(),
          Principal.t() | map(),
          String.t(),
          String.t(),
          map()
        ) ::
          {:ok, Xmtp.RoomPanel.t()} | {:error, term()}
  def complete_join_signature(manager, room_key, principal, request_id, signature, claims \\ %{}) do
    Xmtp.complete_join_signature(manager, room_key, principal, request_id, signature, claims)
  end

  @spec send_message(module(), String.t(), Principal.t() | map(), String.t()) ::
          {:ok, Xmtp.RoomPanel.t()} | {:error, term()}
  def send_message(manager, room_key, principal, body) do
    Xmtp.send_public_message(manager, room_key, principal, body)
  end

  @spec invite(module(), String.t(), Principal.t() | :system, Principal.t() | map(), map()) ::
          {:ok, Xmtp.RoomPanel.t()} | {:error, term()}
  def invite(manager, room_key, inviter, target, claims \\ %{}) do
    Xmtp.invite_user(manager, room_key, inviter, target, claims)
  end

  @spec kick(module(), String.t(), Principal.t() | map(), Principal.t() | map() | String.t()) ::
          {:ok, Xmtp.RoomPanel.t()} | {:error, term()}
  def kick(manager, room_key, moderator, target) do
    Xmtp.kick_user(manager, room_key, moderator, target)
  end

  @spec delete_message(module(), String.t(), Principal.t() | map(), String.t()) ::
          {:ok, Xmtp.RoomPanel.t()} | {:error, term()}
  def delete_message(manager, room_key, moderator, message_id) do
    Xmtp.moderator_delete_message(manager, room_key, moderator, message_id)
  end

  @spec heartbeat(module(), String.t(), Principal.t() | map()) :: :ok
  def heartbeat(manager, room_key, principal), do: Xmtp.heartbeat(manager, room_key, principal)
end

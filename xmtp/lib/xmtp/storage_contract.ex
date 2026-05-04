defmodule Xmtp.StorageContract do
  @moduledoc """
  Describes the optional host-owned XMTP room mirror storage shape.

  This package does not create or own product database tables. Host apps that use
  `Xmtp.RoomServer` copy the matching migration template into their own repo and
  own the resulting tables, retention policy, and product room rules.
  """

  @version "xmtp_room_mirror_v1"
  @tables %{
    rooms: "xmtp_rooms",
    memberships: "xmtp_room_memberships",
    message_logs: "xmtp_message_logs"
  }

  @spec version() :: String.t()
  def version, do: @version

  @spec tables() :: %{rooms: String.t(), memberships: String.t(), message_logs: String.t()}
  def tables, do: @tables

  @spec migration_template_path() :: String.t()
  def migration_template_path do
    :xmtp_elixir_sdk
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("templates/xmtp_room_mirror_v1_migration.exs")
  end
end

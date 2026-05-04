defmodule Xmtp.StorageContractTest do
  use ExUnit.Case, async: true

  alias Xmtp.MessageLog
  alias Xmtp.Room
  alias Xmtp.RoomMembership
  alias Xmtp.StorageContract

  test "contract metadata points at the packaged migration template" do
    assert StorageContract.version() == "xmtp_room_mirror_v1"

    assert StorageContract.tables() == %{
             rooms: "xmtp_rooms",
             memberships: "xmtp_room_memberships",
             message_logs: "xmtp_message_logs"
           }

    assert File.exists?(StorageContract.migration_template_path())
  end

  test "migration template covers the room mirror schemas" do
    template = File.read!(StorageContract.migration_template_path())

    assert template =~ "defmodule YourApp.Repo.Migrations.CreateXmtpRoomMirrorTables"
    assert template =~ "create table(:xmtp_rooms)"
    assert template =~ "create table(:xmtp_room_memberships)"
    assert template =~ "create table(:xmtp_message_logs)"

    assert_schema_fields(template, Room)
    assert_schema_fields(template, RoomMembership)
    assert_schema_fields(template, MessageLog)
  end

  defp assert_schema_fields(template, schema) do
    fields = schema.__schema__(:fields) -- [:id, :inserted_at, :updated_at]

    for field <- fields do
      assert template =~ ":#{field}"
    end
  end
end

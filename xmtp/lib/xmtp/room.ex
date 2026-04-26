defmodule Xmtp.Room do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "xmtp_rooms" do
    field(:room_key, :string)
    field(:conversation_id, :string)
    field(:agent_wallet_address, :string)
    field(:agent_inbox_id, :string)
    field(:status, :string, default: "active")
    field(:capacity, :integer, default: 200)
    field(:room_name, :string)
    field(:description, :string)
    field(:app_data, :string)
    field(:created_at_ns, :integer)
    field(:last_activity_ns, :integer)
    field(:snapshot, :map, default: %{})

    has_many(:memberships, Xmtp.RoomMembership, foreign_key: :room_id)
    has_many(:message_logs, Xmtp.MessageLog, foreign_key: :room_id)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [
      :room_key,
      :conversation_id,
      :agent_wallet_address,
      :agent_inbox_id,
      :status,
      :capacity,
      :room_name,
      :description,
      :app_data,
      :created_at_ns,
      :last_activity_ns,
      :snapshot
    ])
    |> validate_required([
      :room_key,
      :conversation_id,
      :agent_wallet_address,
      :agent_inbox_id,
      :status,
      :capacity,
      :room_name,
      :created_at_ns,
      :last_activity_ns
    ])
    |> validate_inclusion(:status, ["active"])
    |> validate_number(:capacity, greater_than: 0)
    |> unique_constraint(:room_key)
    |> unique_constraint(:conversation_id)
  end
end

defmodule Xmtp.RoomMembership do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Xmtp.Room

  schema "xmtp_room_memberships" do
    field(:wallet_address, :string)
    field(:inbox_id, :string)
    field(:principal_kind, :string, default: "human")
    field(:display_name, :string)
    field(:membership_state, :string, default: "joined")
    field(:last_seen_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    belongs_to(:room, Room)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [
      :room_id,
      :wallet_address,
      :inbox_id,
      :principal_kind,
      :display_name,
      :membership_state,
      :last_seen_at,
      :metadata
    ])
    |> validate_required([
      :room_id,
      :wallet_address,
      :inbox_id,
      :principal_kind,
      :membership_state
    ])
    |> validate_inclusion(:membership_state, ["joined", "kicked"])
    |> validate_inclusion(:principal_kind, ["human", "agent"])
    |> unique_constraint([:room_id, :wallet_address])
    |> unique_constraint([:room_id, :inbox_id])
  end
end

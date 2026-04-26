defmodule Xmtp.MessageLog do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Xmtp.Room

  schema "xmtp_message_logs" do
    field(:xmtp_message_id, :string)
    field(:conversation_id, :string)
    field(:sender_inbox_id, :string)
    field(:sender_wallet, :string)
    field(:sender_kind, :string)
    field(:sender_label, :string)
    field(:body, :string)
    field(:sent_at, :utc_datetime_usec)
    field(:website_visibility_state, :string, default: "visible")
    field(:moderator_wallet, :string)
    field(:moderated_at, :utc_datetime_usec)
    field(:message_snapshot, :map, default: %{})

    belongs_to(:room, Room)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message_log, attrs) do
    message_log
    |> cast(attrs, [
      :room_id,
      :xmtp_message_id,
      :conversation_id,
      :sender_inbox_id,
      :sender_wallet,
      :sender_kind,
      :sender_label,
      :body,
      :sent_at,
      :website_visibility_state,
      :moderator_wallet,
      :moderated_at,
      :message_snapshot
    ])
    |> validate_required([
      :room_id,
      :xmtp_message_id,
      :conversation_id,
      :sender_inbox_id,
      :body,
      :sent_at,
      :website_visibility_state
    ])
    |> validate_inclusion(:website_visibility_state, ["visible", "moderator_deleted"])
    |> unique_constraint(:xmtp_message_id)
  end
end

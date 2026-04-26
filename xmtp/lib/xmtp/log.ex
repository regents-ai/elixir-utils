defmodule Xmtp.Log do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Xmtp.MessageLog
  alias Xmtp.Principal
  alias Xmtp.Room
  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Date, as: XmtpDate
  alias XmtpElixirSdk.Types

  @tombstone_text "message deleted by moderator"

  @spec append_message(module(), Room.t(), Types.Message.t(), map()) ::
          {:ok, MessageLog.t()} | {:error, Ecto.Changeset.t()}
  def append_message(repo, %Room{id: room_id}, message, sender_attrs) do
    attrs = %{
      room_id: room_id,
      xmtp_message_id: message.id,
      conversation_id: message.conversation_id,
      sender_inbox_id: message.sender_inbox_id,
      sender_wallet: Principal.normalize_wallet(Map.get(sender_attrs, :wallet_address)),
      sender_kind: normalize_sender_kind(Map.get(sender_attrs, :kind)),
      sender_label: Map.get(sender_attrs, :label),
      body: render_body(message),
      sent_at: XmtpDate.ns_to_datetime(message.sent_at_ns),
      website_visibility_state: "visible",
      message_snapshot: snapshot(message)
    }

    %MessageLog{}
    |> MessageLog.changeset(attrs)
    |> repo.insert(on_conflict: :nothing, conflict_target: :xmtp_message_id, returning: true)
  end

  @spec list_messages(module(), Room.t()) :: [MessageLog.t()]
  def list_messages(repo, %Room{id: room_id}) do
    MessageLog
    |> where([entry], entry.room_id == ^room_id)
    |> order_by([entry], asc: entry.sent_at, asc: entry.inserted_at)
    |> repo.all()
  end

  @spec get_message(module(), Room.t(), String.t()) :: MessageLog.t() | nil
  def get_message(repo, %Room{id: room_id}, message_id) do
    repo.get_by(MessageLog, room_id: room_id, xmtp_message_id: message_id)
  end

  @spec tombstone_message(module(), Room.t(), String.t(), String.t()) ::
          {:ok, MessageLog.t()} | {:error, :message_not_found | Ecto.Changeset.t()}
  def tombstone_message(repo, room, message_id, moderator_wallet) do
    case get_message(repo, room, message_id) do
      nil ->
        {:error, :message_not_found}

      entry ->
        entry
        |> MessageLog.changeset(%{
          website_visibility_state: "moderator_deleted",
          moderator_wallet: moderator_wallet,
          moderated_at: DateTime.utc_now()
        })
        |> repo.update()
    end
  end

  @spec website_body(MessageLog.t()) :: String.t()
  def website_body(%MessageLog{website_visibility_state: "moderator_deleted"}),
    do: @tombstone_text

  def website_body(%MessageLog{body: body}), do: body

  defp render_body(%Types.Message{content: %Content.Text{text: text}}), do: text
  defp render_body(%Types.Message{content: %Content.Markdown{markdown: markdown}}), do: markdown

  defp render_body(%Types.Message{fallback: fallback})
       when is_binary(fallback) and fallback != "", do: fallback

  defp render_body(%Types.Message{}), do: "[unsupported XMTP content]"

  defp snapshot(message) do
    %{
      id: message.id,
      conversation_id: message.conversation_id,
      sender_inbox_id: message.sender_inbox_id,
      sent_at_ns: message.sent_at_ns,
      delivery_status: message.delivery_status,
      kind: message.kind,
      fallback: message.fallback,
      content_type_id: message.content_type.type_id
    }
  end

  defp normalize_sender_kind(:human), do: "human"
  defp normalize_sender_kind(:agent), do: "agent"
  defp normalize_sender_kind("agent"), do: "agent"
  defp normalize_sender_kind(_), do: "human"
end

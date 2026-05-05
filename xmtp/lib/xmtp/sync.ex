defmodule Xmtp.Sync do
  @moduledoc """
  Phoenix/Postgres-friendly sync helpers for room mirrors.
  """

  alias Xmtp.Log
  alias Xmtp.Room
  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.DecodedMessage
  alias XmtpElixirSdk.Messages
  alias XmtpElixirSdk.Types

  @spec backfill_room(Conversation.t(), keyword()) ::
          {:ok, [DecodedMessage.t()]} | {:error, term()}
  def backfill_room(%Conversation{} = conversation, opts \\ []) do
    since_ns = Keyword.get(opts, :since_ns, 0)
    limit = Keyword.get(opts, :limit, 100)

    Messages.list(conversation, %Types.ListMessagesOptions{
      sent_after_ns: since_ns,
      limit: limit,
      direction: :ascending
    })
  end

  @spec apply_stream_event(map(), keyword()) :: {:ok, term()} | {:error, term()}
  def apply_stream_event(%{message: %Types.Message{} = message}, opts) do
    append_message(message, opts)
  end

  def apply_stream_event(%Types.Message{} = message, opts), do: append_message(message, opts)

  def apply_stream_event(_event, _opts), do: {:error, :unsupported_stream_event}

  @spec idempotency_key(Types.Message.t() | DecodedMessage.t() | map()) :: String.t()
  def idempotency_key(%Types.Message{id: id, conversation_id: conversation_id}) do
    hash_key(conversation_id, id)
  end

  def idempotency_key(%DecodedMessage{id: id, conversation_id: conversation_id}) do
    hash_key(conversation_id, id)
  end

  def idempotency_key(%{id: id, conversation_id: conversation_id})
      when is_binary(id) and is_binary(conversation_id) do
    hash_key(conversation_id, id)
  end

  @spec message_order_key(Types.Message.t() | DecodedMessage.t() | map()) ::
          {non_neg_integer(), String.t()}
  def message_order_key(%Types.Message{id: id, sent_at_ns: sent_at_ns}), do: {sent_at_ns || 0, id}

  def message_order_key(%DecodedMessage{id: id, sent_at_ns: sent_at_ns}),
    do: {sent_at_ns || 0, id}

  def message_order_key(%{id: id, sent_at_ns: sent_at_ns}) when is_binary(id),
    do: {sent_at_ns || 0, id}

  @spec reconcile_membership(Room.t(), [String.t()]) :: %{
          required(:room_key) => String.t(),
          required(:joined_inbox_ids) => [String.t()]
        }
  def reconcile_membership(%Room{} = room, joined_inbox_ids) when is_list(joined_inbox_ids) do
    %{room_key: room.room_key, joined_inbox_ids: Enum.uniq(joined_inbox_ids)}
  end

  defp append_message(message, opts) do
    repo = Keyword.fetch!(opts, :repo)
    room = Keyword.fetch!(opts, :room)
    sender = Keyword.get(opts, :sender, %{})

    Log.append_message(repo, room, message, sender)
  end

  defp hash_key(conversation_id, message_id) do
    Base.encode16(:crypto.hash(:sha256, "#{conversation_id}:#{message_id}"), case: :lower)
  end
end

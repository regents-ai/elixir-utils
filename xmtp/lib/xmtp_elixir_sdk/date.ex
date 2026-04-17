defmodule XmtpElixirSdk.Date do
  @moduledoc """
  Public timestamp helpers for the SDK's nanosecond-based time values.
  """

  alias XmtpElixirSdk.Types

  @spec ns_to_datetime(non_neg_integer()) :: DateTime.t()
  def ns_to_datetime(ns) when is_integer(ns) and ns >= 0 do
    DateTime.from_unix!(div(ns, 1_000_000), :millisecond)
  end

  @spec message_sent_at(Types.Message.t()) :: DateTime.t()
  def message_sent_at(%Types.Message{sent_at_ns: sent_at_ns}), do: ns_to_datetime(sent_at_ns)

  @spec message_expires_at(Types.Message.t()) :: DateTime.t() | nil
  def message_expires_at(%Types.Message{expires_at_ns: nil}), do: nil

  def message_expires_at(%Types.Message{expires_at_ns: expires_at_ns}),
    do: ns_to_datetime(expires_at_ns)

  @spec conversation_created_at(Types.Conversation.t()) :: DateTime.t()
  def conversation_created_at(%Types.Conversation{created_at_ns: created_at_ns}),
    do: ns_to_datetime(created_at_ns)

  @spec conversation_last_activity_at(Types.Conversation.t()) :: DateTime.t()
  def conversation_last_activity_at(%Types.Conversation{last_activity_ns: last_activity_ns}),
    do: ns_to_datetime(last_activity_ns)
end

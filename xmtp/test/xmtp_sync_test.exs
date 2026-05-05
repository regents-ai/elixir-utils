defmodule Xmtp.SyncTest do
  use ExUnit.Case, async: true

  alias Xmtp.Sync
  alias XmtpElixirSdk.Types

  test "message idempotency and ordering are stable" do
    message = %Types.Message{
      id: "message-1",
      conversation_id: "group-1",
      sent_at_ns: 123,
      content_type: %Types.ContentTypeId{
        authority_id: "xmtp.org",
        type_id: "text",
        version_major: 1,
        version_minor: 0
      }
    }

    assert Sync.idempotency_key(message) == Sync.idempotency_key(message)
    assert Sync.message_order_key(message) == {123, "message-1"}
  end

  test "unsupported stream events are explicit" do
    assert {:error, :unsupported_stream_event} = Sync.apply_stream_event(%{kind: :unknown}, [])
  end
end

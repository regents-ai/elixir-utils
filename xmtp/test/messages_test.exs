defmodule XmtpElixirSdk.MessagesTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias XmtpElixirSdk.CodecRegistry
  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.DecodedMessage
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Messages
  defmodule DemoCodec do
    alias XmtpElixirSdk.Types.ContentTypeId

    def content_type do
      %ContentTypeId{
        authority_id: "example.org",
        type_id: "demo",
        version_major: 1,
        version_minor: 0
      }
    end

    def encode(%{body: body}), do: {:ok, %{body: body}}
    def decode(%{body: body}), do: {:ok, %{body: body}}
  end

  setup :start_runtime

  test "send, list, count, publish, and receive events" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, dm} = create_dm(alice, "bob")
    topic = {:messages, dm.id}
    :ok = Events.subscribe(dm, topic)

    assert {:ok, message_id} = Messages.send_text(dm, "hello")
    assert_receive {:xmtp, ^topic, %Events.MessageCreated{message: created}}, 500
    assert created.id == message_id

    assert {:ok, messages} = Messages.list(dm)
    assert {:ok, count} = Messages.count(dm)
    assert count >= 1
    assert Enum.any?(messages, &DecodedMessage.text?/1)

    assert :ok = Messages.publish(dm)
    assert_receive {:xmtp, ^topic, %Events.MessagePublished{conversation_id: conversation_id}}, 500
    assert conversation_id == dm.id
  end

  test "replies and reactions update decoded message state" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])

    assert {:ok, root_id} = Messages.send_text(group, "root")

    reply =
      %Content.Reply{
        reference: root_id,
        reference_inbox_id: alice.inbox_id,
        content: Content.encode_text("reply"),
        content_type: Content.content_type_id(Content.encode_text("reply")),
        in_reply_to: nil
      }

    reaction =
      %Content.Reaction{
        reference: root_id,
        reference_inbox_id: alice.inbox_id,
        action: :added,
        content: "👍",
        schema: :unicode
      }

    assert {:ok, _reply_id} = Messages.send_reply(group, reply)
    assert {:ok, _reaction_id} = Messages.send_reaction(group, reaction)

    assert {:ok, listed} = Messages.list(group)
    root = Enum.find(listed, &(&1.id == root_id))
    assert root.num_replies == 1
    assert length(root.reactions) == 1
  end

  test "custom codecs decode unknown content" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])
    registry = CodecRegistry.new([DemoCodec])

    assert {:ok, unknown} = CodecRegistry.encode(registry, DemoCodec, %{body: "demo"})
    assert {:ok, message_id} = Messages.send(group, unknown)

    assert {:ok, decoded} = Messages.decoded_by_id(alice, message_id, registry)
    assert decoded.decode_status == :decoded
    assert decoded.content == %{body: "demo"}
  end

  test "streamed envelopes append messages" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])

    payload = :erlang.term_to_binary(Content.encode_text("streamed"))
    assert {:ok, [streamed]} = Messages.process_streamed_message(group, payload)
    assert streamed.content.text == "streamed"
  end
end

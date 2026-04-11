defmodule XmtpElixirSdk.RuntimeEventsTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Conversations
  alias XmtpElixirSdk.Events

  setup :start_runtime

  test "two runtimes stay isolated" do
    other_name = XmtpElixirSdk.Runtime.unique_name()
    {:ok, _pid} = XmtpElixirSdk.Runtime.start_link(name: other_name)
    other_runtime = XmtpElixirSdk.Runtime.new(other_name)

    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, other_alice} = Clients.create(other_runtime, identifier("alice"), env: :dev)

    assert alice.runtime != other_alice.runtime
    assert alice.inbox_id == other_alice.inbox_id

    assert {:ok, []} = Conversations.list(alice)
    assert {:ok, []} = Conversations.list(other_alice)

    assert {:ok, group} = create_group(alice, ["bob"])
    assert {:ok, conversations} = Conversations.list(alice)
    assert [group.id] == Enum.map(conversations, & &1.id)
    assert {:ok, []} = Conversations.list(other_alice)
  end

  test "subscribers receive and can stop receiving events" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, _carol} = create_client("carol")
    topic = {:conversations, alice.id}

    :ok = Events.subscribe(alice, topic)
    assert {:ok, group} = create_group(alice, ["bob"])
    assert_receive {:xmtp, ^topic, %Events.ConversationCreated{conversation: created}}, 500
    assert created.id == group.id

    :ok = Events.unsubscribe(alice, topic)
    assert {:ok, _other} = create_group(alice, ["carol"])
    refute_receive {:xmtp, ^topic, _event}, 100
  end
end

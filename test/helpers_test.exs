defmodule XmtpElixirSdk.HelpersTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Conversations
  alias XmtpElixirSdk.InboxId
  alias XmtpElixirSdk.InboxState
  alias XmtpElixirSdk.Installations

  setup :start_runtime

  test "inbox helpers and installation helpers use the new runtime surface" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, inbox_id} = InboxId.fetch(current_runtime(), identifier("alice"))
    assert inbox_id == alice.inbox_id

    assert {:ok, states} = InboxState.fetch(current_runtime(), [alice.inbox_id])
    assert [state] = states

    assert Installations.includes?(state, alice.installation_id)
    assert InboxState.includes_identifier?(state, identifier("alice"))
  end

  test "top level entrypoint requires an explicit runtime" do
    runtime = current_runtime()
    assert {:ok, alice} = XmtpElixirSdk.create_client(runtime, identifier("alice"), env: :dev)
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, dm} = Conversations.create_dm_with_identifier(alice, identifier("bob"))
    assert dm.client.id == alice.id
    assert {:ok, safe_id} = XmtpElixirSdk.generate_inbox_id(identifier("alice"), 0, 1)
    assert is_binary(safe_id)
    assert {:ok, _} = Clients.can_message(runtime, [identifier("alice")])
  end
end

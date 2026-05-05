defmodule XmtpElixirSdk.ClientsTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias XmtpElixirSdk.Clients

  setup :start_runtime

  test "create and build return plain clients tied to the runtime" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, sibling} = build_client("alice")

    assert alice.runtime == current_runtime().name
    assert sibling.runtime == current_runtime().name
    assert alice.inbox_id == sibling.inbox_id
    assert alice.ready?
    refute sibling.ready?
  end

  test "register updates a built client" do
    assert {:ok, built} = build_client("alice")
    refute built.ready?

    assert {:ok, registered} = Clients.register(built)
    assert registered.ready?
    assert {:ok, true} = Clients.is_registered(registered)
  end

  test "account and recovery flows use signature requests" do
    assert {:ok, alice} = create_client("alice")
    alias_identifier = identifier("alice-alias")
    recovery_identifier = identifier("alice-recovery")

    assert {:ok, %{signature_request_id: add_request}} =
             Clients.unsafe_add_account_signature_text(alice, alias_identifier)

    assert :ok = Clients.unsafe_apply_signature_request(alice, add_request, %{})

    assert {:ok, %{signature_request_id: recovery_request}} =
             Clients.unsafe_change_recovery_identifier_signature_text(alice, recovery_identifier)

    assert :ok = Clients.unsafe_apply_signature_request(alice, recovery_request, %{})

    assert {:ok, fetched_inbox_id} =
             Clients.fetch_inbox_id_by_identifier(current_runtime(), alias_identifier)

    assert fetched_inbox_id == alice.inbox_id

    assert {:ok, inbox_state} = XmtpElixirSdk.Preferences.inbox_state(alice)
    assert inbox_state.recovery_identifier == String.downcase(recovery_identifier.identifier)
  end

  test "installation revocation removes sibling installs" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, sibling} = build_client("alice")

    assert :ok = Clients.revoke_installations(alice, [sibling.installation_id], %{})
    assert {:error, _} = Clients.is_registered(sibling)
    assert {:ok, true} = Clients.is_registered(alice)
  end

  test "can_message checks identifier registration" do
    assert {:ok, _alice} = create_client("alice")
    bob = identifier("bob")
    assert {:ok, result} = Clients.can_message(current_runtime(), [identifier("alice"), bob])
    assert result["ethereum:#{String.downcase(identifier("alice").identifier)}"]
    refute result["ethereum:#{String.downcase(bob.identifier)}"]
  end
end

defmodule XmtpElixirSdk.ClientsTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Signer
  alias XmtpElixirSdk.Types
  alias Xmtp.Wallet

  setup :start_runtime

  @alice_private_key Base.decode16!(
                       "59C6995E998F97A5A0044966F094538C5F6C75A5D9E7F0B6E6A0F9F5D4D17CE4"
                     )
  @alias_private_key Base.decode16!(
                       "8B3A350CF5C34C9194CA3A545D3B58DDA73FA08DA3552D9888325D95690B4B4B"
                     )

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
    alice_identifier = wallet_identifier(@alice_private_key)
    alias_identifier = wallet_identifier(@alias_private_key)
    recovery_identifier = identifier("alice-recovery")

    assert {:ok, alice} = Clients.create(current_runtime(), alice_identifier, env: :dev)

    assert {:ok, %{signature_request_id: add_request, signature_text: add_text}} =
             Clients.unsafe_add_account_signature_text(alice, alias_identifier)

    assert :ok =
             Clients.unsafe_apply_signature_request(
               alice,
               add_request,
               signer_for(alias_identifier, add_text, @alias_private_key)
             )

    assert {:ok, %{signature_request_id: recovery_request, signature_text: recovery_text}} =
             Clients.unsafe_change_recovery_identifier_signature_text(alice, recovery_identifier)

    assert :ok =
             Clients.unsafe_apply_signature_request(
               alice,
               recovery_request,
               signer_for(alice.identifier, recovery_text, @alice_private_key)
             )

    assert {:ok, fetched_inbox_id} =
             Clients.fetch_inbox_id_by_identifier(current_runtime(), alias_identifier)

    assert fetched_inbox_id == alice.inbox_id

    assert {:ok, inbox_state} = XmtpElixirSdk.Preferences.inbox_state(alice)
    assert inbox_state.recovery_identifier == String.downcase(recovery_identifier.identifier)
  end

  test "signature requests reject signer payloads for the wrong account" do
    alice_identifier = wallet_identifier(@alice_private_key)
    alias_identifier = wallet_identifier(@alias_private_key)
    assert {:ok, alice} = Clients.create(current_runtime(), alice_identifier, env: :dev)

    assert {:ok, %{signature_request_id: add_request, signature_text: add_text}} =
             Clients.unsafe_add_account_signature_text(alice, alias_identifier)

    assert {:error, %XmtpElixirSdk.Error{kind: :invalid_argument}} =
             Clients.unsafe_apply_signature_request(
               alice,
               add_request,
               signer_for(alice.identifier, add_text, @alice_private_key)
             )
  end

  test "installation revocation removes sibling installs" do
    alice_identifier = wallet_identifier(@alice_private_key)

    assert {:ok, alice} = Clients.create(current_runtime(), alice_identifier, env: :dev)
    assert {:ok, sibling} = Clients.build(current_runtime(), alice_identifier, env: :dev)

    assert {:ok, %{signature_request_id: request_id, signature_text: signature_text}} =
             Clients.unsafe_revoke_installations_signature_text(alice, [sibling.installation_id])

    assert :ok =
             Clients.unsafe_apply_signature_request(
               alice,
               request_id,
               signer_for(alice.identifier, signature_text, @alice_private_key)
             )

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

  test "public key verification requires a real secp256k1 signature" do
    assert {:ok, alice} = create_client("alice")
    signature_text = "authorize installation"
    digest = :crypto.hash(:sha256, signature_text)
    assert {:ok, public_key} = ExSecp256k1.create_public_key(@alice_private_key)
    assert {:ok, {signature, _recovery_id}} = ExSecp256k1.sign_compact(digest, @alice_private_key)

    assert {:ok, true} =
             Clients.verify_signed_with_public_key(alice, signature_text, signature, public_key)

    predictable_hash =
      :crypto.hash(:sha256, "#{Base.encode16(public_key, case: :lower)}:#{signature_text}")

    assert {:ok, false} =
             Clients.verify_signed_with_public_key(
               alice,
               signature_text,
               predictable_hash,
               public_key
             )
  end

  defp wallet_identifier(private_key) do
    {:ok, wallet_address} = Wallet.wallet_address(private_key)
    %Types.Identifier{identifier: wallet_address, identifier_kind: :ethereum}
  end

  defp signer_for(identifier, signature_text, private_key) do
    {:ok, signature} = Wallet.sign_personal_message(private_key, signature_text)
    {:ok, signer} = Signer.eoa(identifier, signature)
    signer
  end
end

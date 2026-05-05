defmodule Xmtp.IdentityTest do
  use ExUnit.Case, async: false

  import XmtpElixirSdk.TestSupport

  alias Xmtp.Identity

  setup :start_runtime

  @wallet "0xabc0000000000000000000000000000000000001"

  test "ensure_identity returns ready when the stored inbox matches the wallet" do
    inbox_id = Identity.derived_inbox_id(@wallet)

    assert {:ok, state} =
             Identity.ensure_identity(%{
               runtime: current_runtime(),
               principal: %{wallet_address: @wallet, inbox_id: inbox_id}
             })

    assert state.status == :ready
    assert state.inbox_id == inbox_id
    assert state.signature_request == nil
  end

  test "ensure_identity deduplicates wallet signature requests" do
    request = %{runtime: current_runtime(), principal: %{wallet_address: @wallet}}

    assert {:ok, first} = Identity.ensure_identity(request)
    assert {:ok, second} = Identity.ensure_identity(request)

    assert first.status == :needs_wallet_signature
    assert first.signature_request.id == second.signature_request.id
    assert first.signature_request.client_id == second.signature_request.client_id
  end

  test "complete_signature registers the client and returns the canonical inbox" do
    assert {:ok, state} =
             Identity.ensure_identity(%{
               runtime: current_runtime(),
               principal: %{wallet_address: @wallet}
             })

    request = state.signature_request

    assert {:ok, completed} =
             Identity.complete_signature(%{
               runtime: current_runtime(),
               wallet_address: @wallet,
               client_id: request.client_id,
               request_id: request.id,
               signature: "signed-by-wallet"
             })

    assert completed.status == :ready
    assert completed.inbox_id == Identity.derived_inbox_id(@wallet)

    assert {:ok, completed.inbox_id} ==
             Identity.ready_inbox_id(%{wallet_address: @wallet}, completed.inbox_id)
  end

  test "unsupported wallet identifiers do not start XMTP registration" do
    assert {:error, :unsupported_wallet} =
             Identity.ensure_identity(%{
               runtime: current_runtime(),
               principal: %{wallet_address: "abc0000000000000000000000000000000000001"}
             })
  end
end

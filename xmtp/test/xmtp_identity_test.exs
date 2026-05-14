defmodule Xmtp.IdentityTest do
  use ExUnit.Case, async: false

  import XmtpElixirSdk.TestSupport

  alias Xmtp.Identity
  alias Xmtp.Wallet

  setup :start_runtime

  @wallet "0xabc0000000000000000000000000000000000001"
  @private_key Base.decode16!("59C6995E998F97A5A0044966F094538C5F6C75A5D9E7F0B6E6A0F9F5D4D17CE4")
  @wrong_private_key Base.decode16!(
                       "8B3A350CF5C34C9194CA3A545D3B58DDA73FA08DA3552D9888325D95690B4B4B"
                     )

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
    wallet = wallet_address(@private_key)

    assert {:ok, state} =
             Identity.ensure_identity(%{
               runtime: current_runtime(),
               principal: %{wallet_address: wallet}
             })

    request = state.signature_request
    signature = signature_for(request.text, @private_key)

    assert {:ok, completed} =
             Identity.complete_signature(%{
               runtime: current_runtime(),
               wallet_address: wallet,
               client_id: request.client_id,
               request_id: request.id,
               signature: signature
             })

    assert completed.status == :ready
    assert completed.inbox_id == Identity.derived_inbox_id(wallet)

    assert {:ok, completed.inbox_id} ==
             Identity.ready_inbox_id(%{wallet_address: wallet}, completed.inbox_id)
  end

  test "complete_signature rejects a signature from another wallet" do
    wallet = wallet_address(@private_key)

    assert {:ok, state} =
             Identity.ensure_identity(%{
               runtime: current_runtime(),
               principal: %{wallet_address: wallet}
             })

    request = state.signature_request
    wrong_signature = signature_for(request.text, @wrong_private_key)

    assert {:error, %XmtpElixirSdk.Error{kind: :invalid_argument}} =
             Identity.complete_signature(%{
               runtime: current_runtime(),
               wallet_address: wallet,
               client_id: request.client_id,
               request_id: request.id,
               signature: wrong_signature
             })
  end

  test "complete_signature rejects a request from another wallet" do
    wallet = wallet_address(@private_key)
    other_wallet = wallet_address(@wrong_private_key)

    assert {:ok, state} =
             Identity.ensure_identity(%{
               runtime: current_runtime(),
               principal: %{wallet_address: wallet}
             })

    assert {:ok, other_state} =
             Identity.ensure_identity(%{
               runtime: current_runtime(),
               principal: %{wallet_address: other_wallet}
             })

    other_request = other_state.signature_request
    signature = signature_for(state.signature_request.text, @private_key)

    assert {:error, :signature_request_mismatch} =
             Identity.complete_signature(%{
               runtime: current_runtime(),
               wallet_address: wallet,
               client_id: other_request.client_id,
               request_id: other_request.id,
               signature: signature
             })
  end

  test "complete_signature rejects an expired request" do
    wallet = wallet_address(@private_key)

    assert {:ok, state} =
             Identity.ensure_identity(%{
               runtime: current_runtime(),
               principal: %{wallet_address: wallet}
             })

    request = state.signature_request
    signature = signature_for(request.text, @private_key)
    expire_signature_request!(wallet, state)

    assert {:error, :signature_request_expired} =
             Identity.complete_signature(%{
               runtime: current_runtime(),
               wallet_address: wallet,
               client_id: request.client_id,
               request_id: request.id,
               signature: signature
             })
  end

  test "unsupported wallet identifiers do not start XMTP registration" do
    assert {:error, :unsupported_wallet} =
             Identity.ensure_identity(%{
               runtime: current_runtime(),
               principal: %{wallet_address: "abc0000000000000000000000000000000000001"}
             })
  end

  defp wallet_address(private_key) do
    {:ok, wallet} = Wallet.wallet_address(private_key)
    wallet
  end

  defp signature_for(text, private_key) do
    {:ok, signature} = Wallet.sign_personal_message(private_key, text)
    signature
  end

  defp expire_signature_request!(wallet, state) do
    true =
      :ets.insert(
        :xmtp_identity_signature_requests,
        {{current_runtime().name, wallet},
         %{expires_at: System.monotonic_time(:millisecond) - 1, state: state}}
      )

    :ok
  end
end

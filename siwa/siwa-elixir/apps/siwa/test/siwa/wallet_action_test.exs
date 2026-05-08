defmodule Siwa.WalletActionTest do
  use ExUnit.Case, async: true

  alias Siwa.{LocalSigner, WalletAction}

  defp wallet_action(overrides \\ %{}) do
    Map.merge(
      %{
        "chain_id" => 8453,
        "to" => "0x1111111111111111111111111111111111111111",
        "value" => "0x0",
        "data" => "0x",
        "expected_signer" => "0x1111111111111111111111111111111111111111",
        "expires_at" => "2099-01-01T00:00:00Z",
        "risk_copy" => "Review this wallet action before signing.",
        "idempotency_key" => "wallet-action-idem-0001"
      },
      overrides
    )
  end

  defp assert_invalid_wallet_action(overrides) do
    assert {:error, :invalid_wallet_action} =
             overrides
             |> wallet_action()
             |> WalletAction.validate()
  end

  test "validates the signed wallet-action policy envelope" do
    assert {:ok, action} = WalletAction.validate(wallet_action())
    assert action["chain_id"] == 8453
  end

  test "rejects wallet actions with missing policy fields" do
    assert {:error, :invalid_wallet_action} =
             wallet_action()
             |> Map.delete("expires_at")
             |> WalletAction.validate()
  end

  test "rejects wallet actions on unsupported chains" do
    assert_invalid_wallet_action(%{"chain_id" => 84_532})
  end

  test "rejects expired wallet actions" do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(-60, :second)
      |> DateTime.to_iso8601()

    assert_invalid_wallet_action(%{"expires_at" => expires_at})
  end

  test "rejects malformed wallet action value and data" do
    assert_invalid_wallet_action(%{"value" => "1"})
    assert_invalid_wallet_action(%{"data" => "0xnot-hex"})
  end

  test "local signer requires the expected signer to match the wallet" do
    {:ok, signer} = LocalSigner.new()
    action = wallet_action(%{"expected_signer" => signer.address})

    assert {:ok, signed} = LocalSigner.sign_transaction(signer, action)
    assert signed.transaction == action
    assert is_map(signed.signature)

    wrong_signer_action =
      wallet_action(%{"expected_signer" => "0x2222222222222222222222222222222222222222"})

    assert LocalSigner.sign_transaction(signer, wrong_signer_action) ==
             {:error, :unexpected_signer}
  end
end

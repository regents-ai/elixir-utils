defmodule Siwa.ReceiptTest do
  use ExUnit.Case, async: true

  @wallet "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"

  test "creates and verifies a receipt" do
    {:ok, receipt} = Siwa.Receipt.create(wallet_receipt(), secret: "secret")

    assert {:ok, payload} =
             Siwa.Receipt.verify(receipt.token, secret: "secret", audience: "techtree")

    assert payload["typ"] == "siwa_wallet_receipt"
    assert payload["sub"] == @wallet
  end

  test "rejects a receipt for the wrong audience" do
    {:ok, receipt} = Siwa.Receipt.create(wallet_receipt(), secret: "secret")

    assert {:error, :receipt_binding_mismatch} =
             Siwa.Receipt.verify(receipt.token, secret: "secret", audience: "platform")
  end

  test "rejects an expired receipt" do
    {:ok, receipt} =
      Siwa.Receipt.create(wallet_receipt(), secret: "secret", now: ~U[2026-04-20 00:00:00Z])

    assert {:error, :invalid_receipt} =
             Siwa.Receipt.verify(receipt.token,
               secret: "secret",
               audience: "techtree",
               now: ~U[2026-04-20 00:31:00Z]
             )
  end

  defp wallet_receipt do
    %{
      "typ" => "siwa_wallet_receipt",
      "verified" => "wallet_signature",
      "jti" => "receipt-test",
      "sub" => @wallet,
      "aud" => "techtree",
      "chain_id" => 8453,
      "nonce" => "nonce-test",
      "key_id" => @wallet
    }
  end
end

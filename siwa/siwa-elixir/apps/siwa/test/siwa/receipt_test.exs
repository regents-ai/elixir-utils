defmodule Siwa.ReceiptTest do
  use ExUnit.Case, async: true

  test "creates and verifies a receipt" do
    {:ok, receipt} =
      Siwa.Receipt.create(
        %{
          "typ" => "siwa_receipt",
          "jti" => "receipt-test",
          "sub" => "0x123",
          "aud" => "techtree",
          "chain_id" => 8453,
          "nonce" => "nonce-test",
          "key_id" => "0x123",
          "registry_address" => "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432",
          "token_id" => "9"
        },
        secret: "secret"
      )

    assert {:ok, payload} =
             Siwa.Receipt.verify(receipt.token, secret: "secret", audience: "techtree")

    assert payload["sub"] == "0x123"
    assert payload["token_id"] == "9"
  end

  test "rejects a receipt for the wrong audience" do
    {:ok, receipt} =
      Siwa.Receipt.create(
        %{
          "typ" => "siwa_receipt",
          "jti" => "receipt-test",
          "sub" => "0x123",
          "aud" => "techtree",
          "chain_id" => 8453,
          "nonce" => "nonce-test",
          "key_id" => "0x123",
          "registry_address" => "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432",
          "token_id" => "9"
        },
        secret: "secret"
      )

    assert {:error, :receipt_binding_mismatch} =
             Siwa.Receipt.verify(receipt.token, secret: "secret", audience: "platform")
  end

  test "rejects an expired receipt" do
    {:ok, receipt} =
      Siwa.Receipt.create(
        %{
          "typ" => "siwa_receipt",
          "jti" => "receipt-test",
          "sub" => "0x123",
          "aud" => "techtree",
          "chain_id" => 8453,
          "nonce" => "nonce-test",
          "key_id" => "0x123",
          "registry_address" => "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432",
          "token_id" => "9"
        },
        secret: "secret",
        now: ~U[2026-04-20 00:00:00Z]
      )

    assert {:error, :invalid_receipt} =
             Siwa.Receipt.verify(receipt.token,
               secret: "secret",
               audience: "techtree",
               now: ~U[2026-04-20 00:31:00Z]
             )
  end
end

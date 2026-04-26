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
          "chain_id" => 84532,
          "nonce" => "nonce-test",
          "key_id" => "0x123",
          "registry_address" => "0x8004a818bfb912233c491871b3d84c89a494bd9e",
          "token_id" => "9"
        },
        secret: "secret"
      )

    assert {:ok, payload} = Siwa.Receipt.verify(receipt.token, secret: "secret")
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
          "chain_id" => 84532,
          "nonce" => "nonce-test",
          "key_id" => "0x123",
          "registry_address" => "0x8004a818bfb912233c491871b3d84c89a494bd9e",
          "token_id" => "9"
        },
        secret: "secret"
      )

    assert {:error, :invalid_receipt} =
             Siwa.Receipt.verify(receipt.token, secret: "secret", audience: "platform")
  end
end

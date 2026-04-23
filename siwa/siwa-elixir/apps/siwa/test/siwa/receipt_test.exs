defmodule Siwa.ReceiptTest do
  use ExUnit.Case, async: true

  test "creates and verifies a receipt" do
    {:ok, receipt} =
      Siwa.Receipt.create(
        %{
          "address" => "0x123",
          "agentId" => 9,
          "agentRegistry" => "eip155:84532:0xregistry",
          "chainId" => 84532
        },
        secret: "secret"
      )

    assert {:ok, payload} = Siwa.Receipt.verify(receipt.token, secret: "secret")
    assert payload["agentId"] == 9
  end

  test "rejects a receipt for the wrong audience" do
    {:ok, receipt} =
      Siwa.Receipt.create(
        %{
          "address" => "0x123",
          "agentId" => 9,
          "agentRegistry" => "eip155:84532:0xregistry",
          "chainId" => 84532,
          "aud" => "techtree"
        },
        secret: "secret"
      )

    assert {:error, :invalid_receipt} =
             Siwa.Receipt.verify(receipt.token, secret: "secret", audience: "platform")
  end
end

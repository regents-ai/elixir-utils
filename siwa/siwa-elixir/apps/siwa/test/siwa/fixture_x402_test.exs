defmodule Siwa.FixtureX402Test do
  use ExUnit.Case, async: true

  test "decodes and processes the frozen JS x402 case" do
    fixture = Siwa.TestFixtures.load("x402")
    data = fixture["case"]

    assert {:ok, decoded} = Siwa.X402.decode_header(data["encoded"])
    assert decoded == data["decoded"]

    payload = %{
      "signature" => "0xsig",
      "payment" => %{
        "scheme" => "exact",
        "network" => "eip155:84532",
        "amount" => "1000",
        "asset" => "USDC",
        "payTo" => "0xabc",
        "nonce" => "nonce-1"
      },
      "resource" => %{
        "url" => "https://api.example.com/weather",
        "description" => "Weather report"
      }
    }

    facilitator = %{
      verify: fn _payload, _accepts -> %{valid: true} end,
      settle: fn _payload, _accepts -> %{success: true, txHash: "0xtxhash"} end
    }

    assert {:ok, processed} =
             Siwa.X402.process_payment(payload, data["decoded"]["accepts"], facilitator)

    assert processed.valid == data["processedPayment"]["valid"]
    assert processed.payment.scheme == data["processedPayment"]["payment"]["scheme"]
    assert processed.payment.network == data["processedPayment"]["payment"]["network"]
    assert processed.payment.amount == data["processedPayment"]["payment"]["amount"]
    assert processed.payment.asset == data["processedPayment"]["payment"]["asset"]
    assert processed.payment.payTo == data["processedPayment"]["payment"]["payTo"]
    assert processed.payment.txHash == data["processedPayment"]["payment"]["txHash"]
  end
end

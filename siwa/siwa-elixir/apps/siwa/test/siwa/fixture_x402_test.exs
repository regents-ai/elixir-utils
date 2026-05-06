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
        "network" => "eip155:8453",
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
      verify: fn _payload, _accepts -> %{"valid" => true} end,
      settle: fn _payload, _accepts -> %{"success" => true, "txHash" => "0xtxhash"} end
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

  test "payment processing requires an accepted payment shape and settlement hash" do
    accepts = [
      %{
        "scheme" => "exact",
        "network" => "eip155:8453",
        "amount" => "1000",
        "asset" => "USDC",
        "payTo" => "0xabc"
      }
    ]

    facilitator = %{
      verify: fn _payload, _accepts -> %{"valid" => true} end,
      settle: fn _payload, _accepts -> %{"success" => true, "txHash" => "0xtxhash"} end
    }

    mismatched_payload = %{
      "payment" => %{
        "scheme" => "exact",
        "network" => "eip155:8453",
        "amount" => "999",
        "asset" => "USDC",
        "payTo" => "0xabc"
      }
    }

    assert {:error, :x402_payment_not_accepted} =
             Siwa.X402.process_payment(mismatched_payload, accepts, facilitator)

    payload = %{
      "payment" => %{
        "scheme" => "exact",
        "network" => "eip155:8453",
        "amount" => "1000",
        "asset" => "USDC",
        "payTo" => "0xabc"
      }
    }

    no_hash_facilitator = %{
      verify: fn _payload, _accepts -> %{"valid" => true} end,
      settle: fn _payload, _accepts -> %{"success" => true} end
    }

    assert {:error, :x402_missing_settlement_hash} =
             Siwa.X402.process_payment(payload, accepts, no_hash_facilitator)
  end

  test "required payment is not accepted from a response header alone" do
    assert {:error, %{status: "payment_required", amount: "1000"}} =
             Siwa.X402.verify(
               %{"headers" => %{"Payment-Response" => "1000"}},
               required: true,
               amount: "1000"
             )
  end
end

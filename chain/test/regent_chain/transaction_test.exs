defmodule RegentChain.TransactionTest do
  use ExUnit.Case, async: true

  alias RegentChain.{Call, Transaction}

  # Foundry's first test account. Each raw transaction below is what `cast mktx`
  # (Foundry 1.5.1) signs from the same fields, and each hash is `cast keccak` of it.
  @key Base.decode16!("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
         case: :lower
       )
  @recipient "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

  test "a USDC transfer on Base signs to the bytes Foundry signs" do
    fields = %{
      chain_id: 8453,
      nonce: 7,
      max_priority_fee_per_gas: 1_000_000,
      max_fee_per_gas: 2_000_000_000,
      gas: 65_000,
      to: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      value: 0,
      data: Call.encode("transfer(address,uint256)", [@recipient, 1_500_000])
    }

    assert Transaction.sign(fields, @key) ==
             {:ok,
              %{
                raw:
                  "0x02f8b082210507830f4240847735940082fde894833589fcd6edb6e08f4c7c32d4f71b54bda0291380b844a9059cbb00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c8000000000000000000000000000000000000000000000000000000000016e360c001a0ac97610fe0d5bc745eb96771e6cdded4e114ebfc1e7bda10326d640f5c9f083fa06c4cbc38d96b338366ece03d126ad806fbafb7586d19a14c7830a0285a196be9",
                hash: "0x1d49a9f4c4cd3755eb39d783b80e5186eb9081fee363f49673b4cefe25779500"
              }}
  end

  test "a plain ETH payment on Base signs to the bytes Foundry signs" do
    fields = %{
      chain_id: 8453,
      nonce: 0,
      max_priority_fee_per_gas: 0,
      max_fee_per_gas: 1_500_000_000,
      gas: 21_000,
      to: @recipient,
      value: 1_000_000_000_000_000,
      data: "0x"
    }

    assert Transaction.sign(fields, @key) ==
             {:ok,
              %{
                raw:
                  "0x02f86f82210580808459682f008252089470997970c51812dc3a010c7d01b50e0d17dc79c887038d7ea4c6800080c001a0887d4c138bc2bb68b7f6703137564b3733ec4119881d51803259a9fcd351daa8a03280faee63b17af96d365bf187e32d550c68e1b7d0704f324d4f6a4f1f1abd6e",
                hash: "0x7238a3f3674f8ba3602ac6b637fb7b9fbd755fbed2caf48d9414aa79c2b0d195"
              }}
  end

  test "the key's address is the account Foundry names for it" do
    assert Transaction.address(@key) == {:ok, "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"}
  end
end

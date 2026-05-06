defmodule Siwa.FixtureNonceTest do
  use ExUnit.Case, async: true

  test "verifies the canonical nonce token fixture" do
    fixture = Siwa.TestFixtures.load("nonce")
    issued = fixture["case"]["nonceIssued"]

    assert {:ok, payload} =
             Siwa.Nonce.verify_nonce_token(
               issued["nonceToken"],
               secret: "fixture-nonce-secret",
               now: ~U[2026-04-17 22:55:00Z]
             )

    assert payload["nonce"] == issued["nonce"]
    assert payload["address"] == "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A"
    assert payload["agent_id"] == 42
    assert payload["agent_registry"] == "eip155:8453:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
    assert payload["audience"] == "techtree"
  end

  test "consumes a canonical stateless nonce token" do
    {:ok, token} =
      Siwa.Nonce.create_nonce_token(
        %{
          "nonce" => "fixture-nonce-1",
          "address" => "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A",
          "agent_id" => 42,
          "agent_registry" => "eip155:8453:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
          "audience" => "techtree",
          "iat" => 1_744_854_400_000,
          "exp" => 4_102_444_800_000
        },
        secret: "fixture-nonce-secret"
      )

    assert {:ok, _payload} =
             Siwa.Nonce.consume(
               %{
                 address: "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A",
                 agent_id: 42,
                 agent_registry: "eip155:8453:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
                 audience: "techtree",
                 nonce: "fixture-nonce-1"
               },
               nonce_token: token,
               secret: "fixture-nonce-secret"
             )
  end
end

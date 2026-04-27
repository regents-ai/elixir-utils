defmodule Siwa.FixtureNonceTest do
  use ExUnit.Case, async: true

  test "verifies the frozen JS nonce token" do
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
    assert payload["agentId"] == 42
    assert payload["agentRegistry"] == "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e"
    assert payload["audience"] == "techtree"
  end

  test "consumes a canonical stateless nonce token" do
    {:ok, token} =
      Siwa.Nonce.create_nonce_token(
        %{
          "nonce" => "fixture-nonce-1",
          "address" => "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A",
          "agentId" => 42,
          "agentRegistry" => "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e",
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
                 agent_registry: "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e",
                 audience: "techtree",
                 nonce: "fixture-nonce-1"
               },
               nonce_token: token,
               secret: "fixture-nonce-secret"
             )
  end
end

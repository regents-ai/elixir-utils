defmodule Siwa.FixtureNonceTest do
  use ExUnit.Case, async: true

  test "verifies the frozen JS nonce token" do
    fixture = Siwa.TestFixtures.load("nonce")
    issued = fixture["case"]["nonceIssued"]

    assert {:ok, payload} = Siwa.Nonce.verify_nonce_token(issued["nonceToken"], secret: "fixture-nonce-secret")
    assert payload["nonce"] == issued["nonce"]
    assert payload["address"] == "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A"
    assert payload["agentId"] == 42
  end

  test "consumes a stateless nonce token" do
    fixture = Siwa.TestFixtures.load("nonce")
    issued = fixture["case"]["nonceIssued"]

    assert {:ok, _payload} =
             Siwa.Nonce.consume(%{
               address: "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A",
               agent_id: 42,
               agent_registry: "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e",
               nonce: issued["nonce"]
             }, nonce_token: issued["nonceToken"], secret: "fixture-nonce-secret")
  end
end

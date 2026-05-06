defmodule SiwaTest do
  use ExUnit.Case, async: true

  test "main API exposes message builder" do
    message =
      Siwa.build_message(%{
        domain: "api.example.com",
        address: "0xabc",
        uri: "https://api.example.com/siwa",
        agent_id: 42,
        agent_registry: "eip155:8453:0xregistry",
        chain_id: 8453,
        nonce: "nonce1234",
        issued_at: "2026-04-17T00:00:00Z"
      })

    assert message =~ "Agent ID: 42"
  end
end

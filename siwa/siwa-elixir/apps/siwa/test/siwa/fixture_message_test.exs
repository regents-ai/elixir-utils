defmodule Siwa.FixtureMessageTest do
  use ExUnit.Case, async: true

  test "matches the frozen JS message shape" do
    fixture = Siwa.TestFixtures.load("message")
    data = fixture["case"]
    input = data["input"]

    built =
      Siwa.Message.build(%{
        domain: input["domain"],
        address: input["address"],
        statement: input["statement"],
        uri: input["uri"],
        agent_id: input["agentId"],
        agent_registry: input["agentRegistry"],
        chain_id: input["chainId"],
        nonce: input["nonce"],
        issued_at: input["issuedAt"]
      })

    assert built == data["builtMessage"]
    assert {:ok, parsed} = Siwa.Message.parse(built)
    assert parsed.domain == data["parsed"]["domain"]
    assert parsed.address == data["parsed"]["address"]
    assert parsed.statement == data["parsed"]["statement"]
    assert parsed.agent_id == data["parsed"]["agentId"]
    assert parsed.agent_registry == data["parsed"]["agentRegistry"]
    assert parsed.chain_id == data["parsed"]["chainId"]
    assert parsed.nonce == data["parsed"]["nonce"]
    assert parsed.issued_at == data["parsed"]["issuedAt"]
  end
end

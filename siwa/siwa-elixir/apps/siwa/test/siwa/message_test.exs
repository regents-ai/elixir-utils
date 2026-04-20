defmodule Siwa.MessageTest do
  use ExUnit.Case, async: true

  test "builds and parses a canonical SIWA message" do
    fields = %{
      domain: "api.example.com",
      address: "0x123",
      statement: "Authenticate as a registered agent.",
      uri: "https://api.example.com/siwa",
      agent_id: 7,
      agent_registry: "eip155:84532:0xregistry",
      chain_id: 84532,
      nonce: "abc12345",
      issued_at: "2026-04-17T00:00:00Z"
    }

    message = Siwa.Message.build(fields)
    assert {:ok, parsed} = Siwa.Message.parse(message)
    assert parsed.agent_id == 7
    assert parsed.statement == fields.statement
  end

  test "unknown string keys stay as strings during normalization" do
    normalized = Siwa.Message.normalize_fields(%{"customField" => "value"})

    assert normalized["customField"] == "value"
    refute Map.has_key?(normalized, :customField)
  end
end

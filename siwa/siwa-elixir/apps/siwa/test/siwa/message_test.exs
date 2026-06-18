defmodule Siwa.MessageTest do
  use ExUnit.Case, async: true

  test "builds and parses a canonical SIWA message" do
    fields = %{
      domain: "api.example.com",
      address: "0x123",
      statement: "Authenticate as a registered agent.",
      uri: "https://api.example.com/siwa",
      agent_id: 7,
      agent_registry: "eip155:8453:0xregistry",
      chain_id: 8453,
      nonce: "abc12345",
      issued_at: "2026-04-17T00:00:00Z"
    }

    message = Siwa.Message.build(fields)
    assert {:ok, parsed} = Siwa.Message.parse(message)
    assert parsed.agent_id == 7
    assert parsed.statement == fields.statement
  end

  test "build accepts canonical string-key fields" do
    message =
      Siwa.Message.build(%{
        "domain" => "api.example.com",
        "address" => "0x123",
        "statement" => "Authenticate as a registered agent.",
        "uri" => "https://api.example.com/siwa",
        "agent_id" => 7,
        "agent_registry" => "eip155:8453:0xregistry",
        "chain_id" => 8453,
        "nonce" => "abc12345",
        "issued_at" => "2026-04-17T00:00:00Z"
      })

    assert message =~ "api.example.com wants you to sign in"
    assert message =~ "Agent ID: 7"
  end

  test "validates the canonical message against expected claims" do
    fields = %{
      domain: "regent.cx",
      address: "0x1111111111111111111111111111111111111111",
      statement: "Sign in to platform.",
      uri: "https://regent.cx/api/shared/siwa/verify",
      agent_id: 77,
      agent_registry: "eip155:8453:0x3333333333333333333333333333333333333333",
      chain_id: 8453,
      nonce: "abc12345",
      issued_at: "2026-04-17T00:00:00Z"
    }

    message = Siwa.Message.build(fields)

    assert :ok = Siwa.Message.validate_canonical(message, fields)

    assert {:error, :invalid_canonical_message} =
             Siwa.Message.validate_canonical(message, %{fields | nonce: "different"})
  end

  test "unknown string keys stay as strings during normalization" do
    normalized = Siwa.Message.normalize_fields(%{"customField" => "value"})

    assert normalized["customField"] == "value"
    refute Map.has_key?(normalized, :customField)
  end

  test "rejects duplicate message fields" do
    message =
      [
        "api.example.com wants you to sign in with your Agent account:",
        "0x123",
        "",
        "URI: https://api.example.com/siwa",
        "Version: 1",
        "Agent ID: 7",
        "Agent Registry: eip155:8453:0xregistry",
        "Chain ID: 8453",
        "Nonce: abc12345",
        "Nonce: duplicate",
        "Issued At: 2026-04-17T00:00:00Z"
      ]
      |> Enum.join("\n")

    assert {:error, :invalid_message} = Siwa.Message.parse(message)
  end

  test "rejects invalid numeric fields" do
    message =
      [
        "api.example.com wants you to sign in with your Agent account:",
        "0x123",
        "",
        "URI: https://api.example.com/siwa",
        "Version: 1",
        "Agent ID: abc",
        "Agent Registry: eip155:8453:0xregistry",
        "Chain ID: 8453",
        "Nonce: abc12345",
        "Issued At: 2026-04-17T00:00:00Z"
      ]
      |> Enum.join("\n")

    assert {:error, :invalid_message} = Siwa.Message.parse(message)
  end
end

# Siwa

Shared Elixir library for Regent SIWA flows.

Use this package when a Regent service needs to:

- build the message an agent signs
- issue and consume nonces
- verify a signed agent sign-in
- create and verify receipts
- verify a signed follow-up request

The shared HTTP contract lives in the Regent shared services OpenAPI file. Keep that contract as the source of truth for public request and response shapes.

## Build A Message

```elixir
message =
  Siwa.build_message(%{
    domain: "regent.cx",
    address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    uri: "https://regent.cx/v1/agent/siwa/verify",
    agent_id: 77,
    agent_registry: "eip155:84532:0x3333333333333333333333333333333333333333",
    chain_id: 84532,
    nonce: "nonce1234",
    issued_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  })
```

## Issue And Consume A Nonce

```elixir
{:ok, nonce} =
  Siwa.create_nonce(%{
    address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    agent_id: 77,
    agent_registry: "eip155:84532:0x3333333333333333333333333333333333333333",
    audience: "regent"
  })

{:ok, _stored_nonce} =
  Siwa.verify_nonce(%{
    address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    agent_id: 77,
    agent_registry: "eip155:84532:0x3333333333333333333333333333333333333333",
    audience: "regent",
    nonce: nonce.nonce
  })
```

## Verify Sign-In

```elixir
{:ok, result} =
  Siwa.verify(message, signature,
    audience: "regent",
    domain: "regent.cx",
    required_services: ["MCP"],
    required_trust_models: ["reputation"]
  )

case result.status do
  "authenticated" -> result.receipt
  "not_registered" -> result.action
  "rejected" -> result.reason
end
```

## Create And Verify A Receipt

```elixir
{:ok, receipt} =
  Siwa.create_receipt(%{
    "typ" => "siwa_receipt",
    "sub" => "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    "chain_id" => 84532,
    "registry_address" => "0x3333333333333333333333333333333333333333",
    "token_id" => "77",
    "aud" => "platform"
  })

{:ok, claims} = Siwa.verify_receipt(receipt.token, audience: "platform")
```

## Development

```bash
mix test
mix format --check-formatted
```

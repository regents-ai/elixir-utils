# Siwa

[Hex package](https://hex.pm/packages/siwa)
[Docs](https://hexdocs.pm/siwa)
[Changelog](CHANGELOG.md)

`siwa` is Regent’s shared Elixir package for agent sign-in, receipts, and signed
service requests.

Use it when a service needs to issue nonces, build SIWA messages, verify signed
messages, create receipts, verify receipts, sign follow-up requests, or verify
follow-up requests from agents and operators.

The package verifies identity and request freshness. The consuming product still
decides whether the verified identity may perform the product action.

## Installation

```elixir
def deps do
  [
    {:siwa, "~> 0.1.1"}
  ]
end
```

## Main Jobs

| Job | Function |
| --- | --- |
| Build the message to sign | `Siwa.build_message/1` |
| Parse a signed message | `Siwa.parse_message/1` |
| Issue a nonce | `Siwa.create_nonce/2` |
| Consume a nonce | `Siwa.verify_nonce/2` |
| Verify a signed sign-in | `Siwa.verify/3` |
| Create a receipt | `Siwa.create_receipt/2` |
| Verify a receipt | `Siwa.verify_receipt/2` |
| Sign a protected request | `Siwa.sign_authenticated_request/4` |
| Verify a protected request | `Siwa.verify_authenticated_request/2` |
| Compute body digest headers | `Siwa.content_digest_for_body/1` |

## Build A Message

```elixir
issued_at =
  DateTime.utc_now()
  |> DateTime.truncate(:second)
  |> DateTime.to_iso8601()

message =
  Siwa.build_message(%{
    domain: "regent.cx",
    address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    uri: "https://regent.cx/v1/agent/siwa/verify",
    agent_id: 77,
    agent_registry: "eip155:8453:0x3333333333333333333333333333333333333333",
    chain_id: 8453,
    nonce: "nonce1234",
    issued_at: issued_at,
    audience: "platform"
  })
```

## Issue And Consume A Nonce

```elixir
{:ok, nonce} =
  Siwa.create_nonce(%{
    address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    agent_id: 77,
    agent_registry: "eip155:8453:0x3333333333333333333333333333333333333333",
    audience: "platform"
  })

{:ok, _stored_nonce} =
  Siwa.verify_nonce(%{
    address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    agent_id: 77,
    agent_registry: "eip155:8453:0x3333333333333333333333333333333333333333",
    audience: "platform",
    nonce: nonce.nonce
  })
```

Nonces are audience-bound and single use.

## Verify Sign-In

```elixir
{:ok, result} =
  Siwa.verify(message, signature,
    audience: "platform",
    domain: "regent.cx",
    required_services: ["MCP"],
    required_trust_models: ["reputation"]
  )

case result.status do
  "authenticated" -> {:ok, result.receipt}
  "not_registered" -> {:error, result.action}
  "rejected" -> {:error, result.reason}
end
```

## Create And Verify A Receipt

```elixir
{:ok, receipt} =
  Siwa.create_receipt(%{
    "typ" => "siwa_receipt",
    "sub" => "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    "chain_id" => 8453,
    "registry_address" => "0x3333333333333333333333333333333333333333",
    "token_id" => "77",
    "aud" => "platform"
  })

{:ok, claims} =
  Siwa.verify_receipt(receipt.token, audience: "platform")
```

Always verify the receipt against the audience that owns the request.

## Sign A Protected Request

```elixir
request = %{
  method: "POST",
  path: "/v1/platform/actions",
  headers: %{"content-type" => "application/json"},
  body: Jason.encode!(%{"action" => "publish"})
}

{:ok, signed_request} =
  Siwa.sign_authenticated_request(request, receipt.token, signer,
    audience: "platform"
  )
```

The request signature is bound to the method, path, selected headers, timestamp,
receipt, and exact body digest.

## Verify A Protected Request

```elixir
{:ok, verified} =
  Siwa.verify_authenticated_request(signed_request,
    audience: "platform",
    replay_store: Siwa.RequestAuth.ReplayStore
  )
```

Verify the signature before consuming replay state, and keep product permission
checks outside this package.

## Wallet Actions

`Siwa.WalletAction` validates wallet-ready action envelopes for transaction and
authorization signing. Use it before handing a prepared action to a signer.

```elixir
{:ok, action} = Siwa.WalletAction.validate(action)
:ok = Siwa.WalletAction.require_expected_signer(action, signer_address)
```

## What This Package Does Not Do

- It does not own product sessions.
- It does not decide product permissions.
- It does not store product workflow state.
- It does not expose private keys.
- It does not submit transactions.

## Development

```bash
mix deps.get
mix test
mix docs
```

# agent_world

[Hex package](https://hex.pm/packages/agent_world)
[Docs](https://hexdocs.pm/agent_world)
[Changelog](CHANGELOG.md)

`agent_world` provides shared Elixir helpers for AgentKit headers, AgentBook
lookups, and World-backed registration sessions.

Use it when a Regent product needs trust evidence. The package parses and
verifies evidence, prepares registration requests, and normalizes lookup
results. The product app decides what that evidence means for profile state,
trust labels, permissions, and user flows.

## Installation

```elixir
def deps do
  [
    {:agent_world, "~> 0.1.0"}
  ]
end
```

When building this package from this repository against the published SIWA Hex
package:

```bash
SIWA_HEX_PUBLISH=1 mix deps.get
```

## When To Use It

Use `agent_world` for:

- parsing AgentKit headers
- checking AgentKit message freshness and protected-resource binding
- verifying EVM signatures, including ERC-1271 contract-wallet signatures when an RPC URL is supplied
- looking up an AgentBook human id for a wallet
- creating World registration sessions
- turning a World proof into a wallet-ready AgentBook registration request
- checking a submitted registration transaction before marking a product flow complete

Use product code for:

- the World App verification screen
- product trust session records
- public profile text
- permission decisions
- deciding when evidence is enough to show a verified, claimed, pending, failed, or unknown trust state

## AgentKit Headers

Parse the header:

```elixir
{:ok, payload} =
  AgentWorld.parse_agentkit_header(agentkit_header)
```

Validate that the message was intended for the protected resource:

```elixir
{:ok, %{valid: true}} =
  AgentWorld.validate_agentkit_message(
    payload,
    "https://platform.regent.cx/v1/company/acme"
  )
```

Verify the signature:

```elixir
{:ok, %{valid: true, address: address}} =
  AgentWorld.verify_agentkit_signature(payload,
    rpc_url: "https://mainnet.base.org"
  )
```

If the payload is signed by an externally owned account, the package recovers
the signer from the EVM personal-sign signature. If the signer is a contract
wallet, pass an RPC URL so the package can check ERC-1271.

## AgentBook Lookup

Look up the human id associated with an agent wallet:

```elixir
{:ok, human_id_or_nil} =
  AgentWorld.AgentBook.lookup_human(
    "0x1111111111111111111111111111111111111111",
    "base",
    rpc_url: "https://mainnet.base.org"
  )
```

Use lookup results as evidence snapshots. Store product workflow state in the
product app.

## Registration Sessions

Create a pending registration session:

```elixir
{:ok, session} =
  AgentWorld.Registration.create_session(%{
    "agent_address" => "0x1111111111111111111111111111111111111111",
    "network" => "base",
    "rpc_url" => "https://mainnet.base.org",
    "world_id" => %{
      "app_id" => "app_...",
      "action" => "agentbook-register",
      "rp_id" => "platform.regent.cx",
      "signing_key" => System.fetch_env!("WORLD_ID_SIGNING_KEY")
    }
  })
```

The session includes a nonce, signal, relying-party context, expiry, and network
metadata. Product code should store the session and pass the session fields to
the World App flow it owns.

Submit a proof:

```elixir
{:ok, next_state} =
  AgentWorld.Registration.submit_proof(session, proof_payload, submission: :manual)
```

With manual submission, the result contains an `%AgentWorld.TxRequest{}`. Send
that request through the product’s wallet or signer.

Confirm a submitted transaction:

```elixir
{:ok, confirmed} =
  AgentWorld.Registration.register_transaction(tx_hash, session)
```

Only mark the product trust session complete after the transaction is confirmed.

## Network Configuration

Built-in network ids:

- `"world"`
- `"base"`
- `"base-sepolia"`

Override network details in config:

```elixir
config :agent_world,
  networks: %{
    "base" => %{
      rpc_url: System.fetch_env!("BASE_RPC_URL")
    }
  },
  world_id: %{
    app_id: System.fetch_env!("WORLD_ID_APP_ID"),
    action: "agentbook-register",
    rp_id: "platform.regent.cx",
    signing_key: System.fetch_env!("WORLD_ID_SIGNING_KEY")
  }
```

## Return Shapes

Successful calls return `{:ok, value}`. Failures return
`{:error, %AgentWorld.Error{}}`.

Use error `kind` for program behavior and error `message` for diagnostics.

## What This Package Does Not Do

- It does not own World App UI.
- It does not store product trust sessions.
- It does not decide product permissions.
- It does not make AgentBook evidence a universal authorization grant.
- It does not store full World proof payloads unless the product chooses to.

## Development

```bash
mix deps.get
mix test
mix docs
```

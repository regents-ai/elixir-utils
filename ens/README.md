# ens-elixir

[Changelog](CHANGELOG.md)

Elixir-first [ENSIP-25](https://docs.ens.domains/ensip/25) package for checking
and preparing the link between ENS names and AI agent registry entries such as
ERC-8004.

This package ports the core ENSIP-25 helper surface from
[qntx/ensip25](https://github.com/qntx/ensip25) and keeps the higher-level
planning and unsigned transaction helpers needed by Phoenix apps and CLI tools.

## Installation

Add `ens_elixir` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ens_elixir, "~> 0.1.0"}
  ]
end
```

## Scope

- The package owns ENSIP-25 encoding, key building, verification, and name handling.
- The package includes read-only planning and unsigned transaction preparation for ENS and ERC-8004 linking flows.
- Signing and broadcasting stay in the caller.

## Public Surface

- `AgentEns` for the main entrypoint
- `AgentEns.ERC7930` for interoperable address encode and decode
- `AgentEns.RecordKey` for ENSIP-25 text record keys
- `AgentEns.Verify` for JSON-RPC backed verification
- `AgentEns.Error` for structured package errors
- `AgentEns.Plan` for read-only link planning
- `AgentEns.Link` for preparing unsigned ENS and ERC-8004 updates
- `AgentEns.Tx` and `AgentEns.TxRequest` for unsigned transaction payloads
- `AgentEns.ERC8004.Registration` for registration fetch, patch, and publish helpers
- `AgentEns.Networks` for built-in network defaults
- `AgentEns.Normalize` for ENS normalization and namehash preparation

## Examples

Offline record-key generation:

```elixir
iex> AgentEns.evm_record_key(1, "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432", 42)
{:ok, "agent-registration[0x000100000101148004a169fb4a3325136eb29fa0ceb6d2e539a432][42]"}
```

Verify an ENS name against a specific registry entry:

```elixir
iex> AgentEns.verify(
...>   "https://eth.llamarpc.com",
...>   "vitalik.eth",
...>   1,
...>   "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
...>   42
...> )
{:ok, :verified}
```

Verify with a built-in ERC-8004 network mapping:

```elixir
iex> AgentEns.verify_agent(
...>   "https://eth.llamarpc.com",
...>   :ethereum_mainnet,
...>   42,
...>   "vitalik.eth"
...> )
{:ok, :verified}
```

Generate a read-only link plan:

```elixir
iex> AgentEns.plan_link(%{
...>   ens_name: "vitalik.eth",
...>   chain_id: 1,
...>   registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
...>   agent_id: 42,
...>   rpc_url: "https://eth.llamarpc.com"
...> })
{:ok, %AgentEns.Plan.LinkPlan{}}
```

Prepare unsigned ENS and ERC-8004 updates:

```elixir
iex> AgentEns.prepare_bidirectional_link(%{
...>   ens_name: "vitalik.eth",
...>   chain_id: 1,
...>   registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
...>   agent_id: 42,
...>   rpc_url: "https://eth.llamarpc.com",
...>   signer_address: "0x1234..."
...> })
{:ok,
 %{
   plan: %AgentEns.Plan.LinkPlan{},
   ensip25: %{tx: %AgentEns.TxRequest{}},
   erc8004: %{tx: %AgentEns.TxRequest{}},
   reverse: :skipped
 }}
```

## Notes

- Verification uses lightweight JSON-RPC `eth_call` requests through `Req`.
- ENS normalization uses UTS-46 compatibility processing before namehashing.
- Built-in ERC-8004 mappings ship for Ethereum mainnet and Sepolia.
- Registration publishing stays pluggable so callers can choose their own storage flow.

## Publishing

Build the package locally with:

```bash
mix hex.build
```

Publish it with:

```bash
mix hex.publish
```

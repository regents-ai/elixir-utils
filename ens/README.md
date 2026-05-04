# ens-elixir

[Changelog](CHANGELOG.md)

`ens_elixir` helps an Elixir app work with ENS names when the job is to:

- prove that an ENS name points at an agent record
- inspect the current state of a name or subname
- figure out what needs to change before asking a person to approve anything
- prepare wallet-ready requests for ENS, reverse records, subnames, and ERC-8004 registration updates

It is a library package. It reads ENS state, explains what is missing, and prepares the next request to send. Your app, wallet, or signer still decides whether to approve and send that request.

This package ports the core [ENSIP-25](https://docs.ens.domains/ensip/25) helpers from [qntx/ensip25](https://github.com/qntx/ensip25) and adds the higher-level tools needed by CLI tools and Phoenix apps.

## Installation

Add `ens_elixir` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ens_elixir, "~> 0.1.0"}
  ]
end
```

## Start Here

Most apps only need one of these entry points:

- `AgentEns.verify/6` when you only want to know whether an ENS name already proves the link
- `AgentEns.read_name/1` when you want a fuller picture of a name or subname
- `AgentEns.plan_link/1` when you want to know what is missing before asking a person to approve changes
- `AgentEns.prepare_bidirectional_link/1` when you want the next unsigned requests for both sides of the link

If you are building a custom flow, use `AgentEns.Tx` for one-off ENS and subname changes.

## Quick Examples

Build the ENSIP-25 record key for an EVM registry entry:

```elixir
iex> AgentEns.evm_record_key(1, "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432", 42)
{:ok, "agent-registration[0x000100000101148004a169fb4a3325136eb29fa0ceb6d2e539a432][42]"}
```

Check whether an ENS name already proves the link:

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

Read the current state of a name:

```elixir
iex> AgentEns.read_name(%{
...>   ens_name: "vitalik.eth",
...>   chain_id: 1,
...>   rpc_url: "https://eth.llamarpc.com",
...>   text_keys: ["avatar", "url"]
...> })
{:ok, %AgentEns.Read.NameDetails{}}
```

Plan what needs to change before prompting a signer:

```elixir
iex> AgentEns.plan_link(%{
...>   ens_name: "vitalik.eth",
...>   chain_id: 1,
...>   registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
...>   agent_id: 42,
...>   rpc_url: "https://eth.llamarpc.com",
...>   signer_address: "0x1234..."
...> })
{:ok, %AgentEns.Plan.LinkPlan{}}
```

Prepare the next unsigned requests for both sides of the link:

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

Prepare an unsigned request to create or update a subname:

```elixir
iex> AgentEns.Tx.build_create_subname_tx(%{
...>   parent_name: "vitalik.eth",
...>   chain_id: 1,
...>   label: "agent",
...>   owner_address: "0x1234...",
...>   resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
...>   ttl: 0
...> })
{:ok, %AgentEns.TxRequest{}}
```

## What You Get Back

The package always returns one of two shapes:

- `{:ok, value}` when the work succeeded
- `{:error, %AgentEns.Error{}}` when something is missing, invalid, unsupported, or unreachable

When the package prepares a change, it returns `%AgentEns.TxRequest{}`. That is a wallet-ready request with:

- where the request should go
- the encoded call data
- the chain it belongs to
- the wallet that is expected to approve it, when known
- when the request should no longer be used
- a short review note for the person approving it
- a stable marker for this one request
- a short human description of what the request does

The package does not send that request for you.

## Common Jobs

### 1. Check an existing link

Use `AgentEns.verify/6` when you already know the chain, registry, and agent ID and only want a yes-or-no answer.

Use `AgentEns.verify_agent/5` when the registry is one of the built-in ERC-8004 defaults for Ethereum mainnet or Sepolia.

### 2. Inspect a name before showing UI

Use `AgentEns.read_name/1` when you want to show a person who controls a name, which resolver it uses, whether it has an ETH address, whether it has a content hash, and which text records are present.

### 3. Decide what should happen next

Use `AgentEns.plan_link/1` when you want to know:

- whether the ENS proof is already present
- whether the ERC-8004 registration already points back to the ENS name
- whether the current signer can make the needed changes
- whether a reverse record can also be updated

This is the safest starting point for a UI that wants to explain the situation before asking for approval.

### 4. Prepare updates

Use `AgentEns.prepare_ensip25_update/1` when you only need the ENS proof record.

Use `AgentEns.prepare_erc8004_update/1` when you only need to patch the agent registration.

Use `AgentEns.prepare_bidirectional_link/1` when you want the full answer in one call.

Use `AgentEns.Tx` when you want to prepare other ENS changes such as:

- setting text records
- changing the ETH address
- changing the content hash
- changing the resolver
- changing TTL
- creating or updating subnames
- setting the reverse name

## Built-In Network Defaults

The package ships with default ENS and ERC-8004 addresses for:

- Ethereum mainnet
- Ethereum Sepolia

You can still pass explicit addresses whenever you want to override those defaults.

## What This Package Does Not Do

- It does not manage private keys.
- It does not ask a wallet for approval.
- It does not send requests to the chain.
- It does not store your registrations for you unless you provide a publisher when updating ERC-8004 data.

## Full Guide

For a fuller walkthrough of the package, see [USAGE.md](USAGE.md).

## Publishing

Build the package locally with:

```bash
mix hex.build
```

Publish it with:

```bash
mix hex.publish
```

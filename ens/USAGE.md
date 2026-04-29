# Using ens-elixir

This guide explains the package as a set of practical jobs instead of a list of modules.

## The Short Version

The package helps with four things:

1. Turn an ENS name into something your app can trust.
2. Read what is already set on a name or subname.
3. Decide what needs to change before asking for approval.
4. Prepare the next request to send.

If you remember only one rule, remember this one:

- `AgentEns.Plan` tells you what is true now.
- `AgentEns.Link` tells you what to do next.
- `AgentEns.Tx` builds one specific request when you already know what you want.

## The Main Inputs

Most flows use the same small set of inputs:

- `ens_name`: the ENS name you care about, such as `"alice.eth"`
- `chain_id`: the chain where the ENS name and agent registry live
- `rpc_url`: a JSON-RPC endpoint for that chain
- `registry_address`: the ERC-8004 registry address
- `agent_id`: the agent entry you want the name to prove
- `signer_address`: the address that might approve changes

Some flows also use:

- `resolver_address`: the resolver you want to write to
- `reverse_registrar`: the reverse name contract when you want to set a primary name
- `text_keys`: text records you want to read

## Pick the Right Starting Point

### I only want to know whether the link already exists

Use `AgentEns.verify/6`.

It answers one question: does this ENS name already contain the right proof record for this registry entry?

Expected result:

- `{:ok, :verified}` when the name already proves the link
- `{:ok, :ens_record_missing}` when the proof record is missing or empty
- `{:error, error}` when the name, resolver, network, or request is invalid or unreachable

### I want to show the current state of a name

Use `AgentEns.read_name/1`.

This is the best choice when you are building a details page, a review screen, or a CLI inspect command.

It can tell you:

- the normalized form of the name
- whether the name exists
- who controls it
- whether it is wrapped
- which resolver it uses
- which resolver features appear to be available
- the current ETH address
- the current content hash
- any text records you asked for
- warnings about important edge cases

Example:

```elixir
AgentEns.read_name(%{
  ens_name: "alice.eth",
  chain_id: 1,
  rpc_url: "https://eth.llamarpc.com",
  text_keys: ["avatar", "url", "com.twitter"]
})
```

### I want to know what is missing before asking for approval

Use `AgentEns.plan_link/1`.

This is the best starting point for most apps. It gives you a read-only snapshot of the current link state and tells you which actions are ready, blocked, already done, or skipped.

The plan helps answer:

- Is the ENS proof already there?
- Does the agent registration already point back to the ENS name?
- Does the current signer control the ENS name?
- Does the current signer control the agent entry?
- Can a reverse name also be set?

This lets you explain the situation clearly before you show an approval screen.

Example:

```elixir
AgentEns.plan_link(%{
  ens_name: "alice.eth",
  chain_id: 1,
  registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
  agent_id: 42,
  rpc_url: "https://eth.llamarpc.com",
  signer_address: "0x1234..."
})
```

### I want the next unsigned requests

Use `AgentEns.prepare_bidirectional_link/1`.

This call runs the plan first, then prepares the next available requests for:

- the ENS proof record
- the ERC-8004 registration update
- the reverse name update when requested

Each branch comes back as one of:

- a prepared result with a request inside it
- `:noop` when nothing needs to change
- `:blocked` when the package can see that the change cannot be prepared from the current inputs
- `:skipped` for reverse name updates that were not requested

## Working With the Returned Request

When the package prepares a change, you get `%AgentEns.TxRequest{}`.

Think of it as a ready-to-send instruction for a wallet:

- `to`: the contract that should receive the request
- `data`: the encoded request data
- `value`: the amount of native token to send with it, usually `0`
- `chain_id`: the target chain
- `expected_signer`: the wallet expected to approve it, when known
- `expires_at`: when the request should no longer be used
- `risk`: a short review note for the person approving it
- `description`: a short sentence you can show in logs or review screens

The package stops there. Your app or wallet decides whether to approve and send it.

## Common Workflows

### Verify a link

Use this when you are checking an existing setup:

```elixir
AgentEns.verify(
  "https://eth.llamarpc.com",
  "alice.eth",
  1,
  "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
  42
)
```

If you are using one of the built-in ERC-8004 networks:

```elixir
AgentEns.verify_agent(
  "https://eth.llamarpc.com",
  :ethereum_mainnet,
  42,
  "alice.eth"
)
```

### Read a name and selected text records

```elixir
AgentEns.read_name(%{
  ens_name: "alice.eth",
  chain_id: 1,
  rpc_url: "https://eth.llamarpc.com",
  text_keys: ["avatar", "description"]
})
```

### Plan a full ENS <-> ERC-8004 link

```elixir
AgentEns.plan_link(%{
  ens_name: "alice.eth",
  chain_id: 1,
  registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
  agent_id: 42,
  rpc_url: "https://eth.llamarpc.com",
  signer_address: "0x1234..."
})
```

### Prepare only the ENS proof update

```elixir
AgentEns.prepare_ensip25_update(%{
  ens_name: "alice.eth",
  chain_id: 1,
  registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
  agent_id: 42,
  rpc_url: "https://eth.llamarpc.com",
  signer_address: "0x1234..."
})
```

### Prepare only the ERC-8004 update

```elixir
AgentEns.prepare_erc8004_update(%{
  ens_name: "alice.eth",
  chain_id: 1,
  registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
  agent_id: 42,
  rpc_url: "https://eth.llamarpc.com",
  signer_address: "0x1234..."
})
```

### Prepare a general ENS change

The `AgentEns.Tx` module is for focused one-off jobs.

Set a text record:

```elixir
AgentEns.Tx.build_set_text_record_tx(%{
  ens_name: "alice.eth",
  chain_id: 1,
  resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
  key: "url",
  value: "https://example.com"
})
```

Set an ETH address:

```elixir
AgentEns.Tx.build_set_addr_tx(%{
  ens_name: "alice.eth",
  chain_id: 1,
  resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
  address: "0x1111111111111111111111111111111111111111"
})
```

Create or update a subname:

```elixir
AgentEns.Tx.build_create_subname_tx(%{
  parent_name: "alice.eth",
  chain_id: 1,
  label: "agent",
  owner_address: "0x1111111111111111111111111111111111111111",
  resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
  ttl: 0
})
```

Set the primary name:

```elixir
AgentEns.Tx.build_reverse_set_name_tx(%{
  chain_id: 1,
  ens_name: "alice.eth"
})
```

## ERC-8004 Registration Files

`AgentEns.ERC8004.Registration` helps when the link also needs to be written into the agent registration itself.

It can:

- fetch the current registration
- parse JSON or supported data links
- update or insert the ENS service entry
- serialize the result
- hand the updated content to a publisher that returns a new URI

This is useful when you want your app to keep the agent record and the ENS name in sync.

## Network Defaults

The package ships with network defaults for:

- Ethereum mainnet
- Ethereum Sepolia

That includes the ENS registry, name wrapper, reverse registrar, and ERC-8004 registry for those networks.

If you are working somewhere else, pass the addresses directly.

## What to Show a Person

If you are building a UI or CLI, these are the most useful messages to surface:

- whether the ENS proof already exists
- whether the agent registration already points back to the name
- who controls the ENS name
- whether the current signer can make the needed changes
- whether a reverse name can also be set
- any warnings returned by the read or plan step

In practice, `read_name/1` and `plan_link/1` give you almost everything you need for a review screen.

## Good Defaults for App Flows

If you are unsure how to structure your flow, this is a solid order:

1. Call `AgentEns.read_name/1` for the details page.
2. Call `AgentEns.plan_link/1` before asking for approval.
3. Show the person what is already done and what still needs to change.
4. Call `AgentEns.prepare_bidirectional_link/1` only after the person decides to proceed.
5. Hand the resulting request to the wallet or signer you already use.

## Module Map

- `AgentEns`: the best starting point for most callers
- `AgentEns.Verify`: yes-or-no ENSIP-25 verification
- `AgentEns.Read`: richer name inspection
- `AgentEns.Plan`: read-only link planning
- `AgentEns.Link`: prepare the next unsigned updates
- `AgentEns.Tx`: build one specific ENS, reverse, or subname request
- `AgentEns.RecordKey`: build ENSIP-25 text record keys
- `AgentEns.ERC7930`: encode or decode interoperable registry addresses
- `AgentEns.ERC8004.Registration`: read and patch ERC-8004 registration files
- `AgentEns.Networks`: built-in chain defaults
- `AgentEns.Normalize`: ENS name normalization helpers

## Final Advice

If your app needs only one safe starting point, use `AgentEns.plan_link/1`.

It gives you the clearest picture of what is already true, what is missing, and whether the next step is ready before you ask a person to approve anything.

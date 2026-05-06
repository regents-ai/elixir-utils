# regent_cache

[Hex package](https://hex.pm/packages/regent_cache)
[Docs](https://hexdocs.pm/regent_cache)
[Changelog](CHANGELOG.md)

`regent_cache` is the shared Cachex helper package for Regent Elixir apps.

Use it for short-lived read projections, external lookup snapshots, counters,
and set membership helpers where the cache can be missed or rebuilt without
changing product truth.

Do not use it as the owner of workflow state, permissions, balances, ownership,
staking, revenue, secrets, receipts, private keys, or access tokens.

## Installation

```elixir
def deps do
  [
    {:regent_cache, "~> 0.1.0"}
  ]
end
```

## Start A Cache

Add a Cachex process under your supervisor:

```elixir
children = [
  RegentCache.child_spec(:my_app_cache)
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Check whether the cache is reachable:

```elixir
case RegentCache.status(:my_app_cache) do
  :ready -> :ok
  {:error, reason} -> {:error, reason}
end
```

## Store And Fetch JSON

Use `fetch/4` when the cache should wrap a canonical read:

```elixir
RegentCache.fetch(:my_app_cache, "platform:company:v1:42:profile", 300, fn ->
  {:ok, %{"name" => "Acme", "status" => "published"}}
end)
```

Use direct JSON helpers when you already have the value:

```elixir
:ok =
  RegentCache.put_json(
    :my_app_cache,
    "techtree:node:v1:node_123:summary",
    %{"title" => "Review Packet", "visible" => true},
    120
  )

{:ok, summary} =
  RegentCache.get_json(:my_app_cache, "techtree:node:v1:node_123:summary")
```

`get_json/2` returns:

- `{:ok, value}` for a valid cached value
- `:miss` when the key is absent
- `{:error, reason}` when the cached value is not valid JSON or Cachex fails

## Strings, Counters, And Sets

```elixir
{:ok, next_count} =
  RegentCache.increment(:my_app_cache, "siwa:request:v1:rate:agent_77", 60)

:ok =
  RegentCache.set_add(:my_app_cache, "xmtp:room:v1:company:acme:active", "wallet:0xabc", 30)

{:ok, active_members} =
  RegentCache.set_members(:my_app_cache, "xmtp:room:v1:company:acme:active")

:ok =
  RegentCache.set_remove(:my_app_cache, "xmtp:room:v1:company:acme:active", "wallet:0xabc", 30)
```

## Key Shape

Use product-prefixed, versioned keys:

```text
platform:company:v1:<company_id>:public_profile
autolaunch:subject:v1:<subject_id>:trust_summary
techtree:node:v1:<node_id>:public_projection
siwa:request:v1:<agent_id>:rate
xmtp:room:v1:<room_key>:active
```

Include chain id and contract address when the cached value comes from chain
state. Keep values bounded, and prefer short TTLs for anything that can affect
what a person sees or can do.

## Good Uses

- Public profile projections
- Short-lived chain or ENS read snapshots
- External trust lookup snapshots with `observed_at`
- Idempotency helper state when the product defines the owner
- Rate-limit counters
- Ephemeral room presence

## Bad Uses

- Product workflow records
- Authorization decisions with long TTLs
- Balances, ownership, staking, revenue, or settlement state
- Private keys, raw tokens, receipts, or signatures
- Billing secrets or push secrets
- Unbounded user-controlled JSON

## Development

```bash
mix deps.get
mix test
mix docs
```

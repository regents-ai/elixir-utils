# Regent Elixir Utilities

This repository holds the shared Elixir packages used by Regent services and
Phoenix apps.

Each package has one job. Product apps decide what a feature means for users;
these packages provide the reusable identity, messaging, signing, trust, and
cache tools behind those features.

Techtree proof and Fold policy are Techtree product records. Shared SIWA and
utility packages prove identity or provide helper evidence; they do not decide
benchmark proof status or Fold reward eligibility.

## Packages

| Folder | Hex package | Use it for | Use it in |
| --- | --- | --- | --- |
| `siwa/siwa-elixir/apps/siwa` | `siwa` | Agent sign-in messages, nonces, receipts, signed request checks, wallet action envelopes, Ethereum helpers, and payment header parsing. | Shared SIWA service, product APIs that verify signed agent/operator requests, CLI-backed service calls. |
| `siwa/siwa-elixir/apps/siwa_keyring` | `siwa_keyring` | Isolated local wallet creation and signing behind an internal HMAC-protected service. | Shared SIWA deployments, internal signing sidecars, services that need a wallet without exposing private keys to the caller. |
| `ens/` | `ens_elixir` | ENS name reads, ENSIP-25 verification, ERC-8004 registration helpers, link planning, and wallet-ready unsigned ENS requests. | Platform trust linking, Autolaunch trust follow-up, CLI ENS commands, any app that needs to show or prepare ENS identity work. |
| `xmtp/` | `xmtp_elixir_sdk` | XMTP client lifecycle, conversations, groups, messages, sync helpers, product-scoped room panels, identity setup, resolver caching, and room metadata. | Platform Regent rooms, Autolaunch launch or subject rooms, Techtree public/review/research rooms, server-owned room workers. |
| `world/agentbook/` | `agent_world` | AgentKit header parsing, AgentBook lookup, World proof registration sessions, and wallet-ready AgentBook registration requests. | Product trust sessions, Autolaunch trust summaries, Platform identity checks, CLI trust-link commands. |
| `cache/` | `regent_cache` | Cachex-backed JSON values, strings, counters, sets, health checks, and cache child specs. | Short-lived read projections in Platform, Autolaunch, Techtree, SIWA, and shared workers. |
| `kohaku/plugins/` | `kohaku_plugins` | Kohaku host, storage, keystore, asset, balance, and broadcaster primitives. | Shared Kohaku protocol package foundations. |
| `kohaku/provider/` | `kohaku_provider` | Ethereum JSON-RPC reads, calls, receipts, transaction submission, and Anvil test helpers. | Kohaku protocol packages and forked-chain tests. |
| `kohaku/railgun/` | `railgun_elixir` | Railgun chain config, signers, syncing, balances, shield, transfer, unshield, and broadcast helpers. | Server-owned Railgun flows and Kohaku privacy-provider tests. |

## Choosing The Right Package

Use `siwa` when the question is: “Who signed this Regent request, what audience
was it for, and is the receipt still valid?”

Use `siwa_keyring` when a process needs a signing wallet but should not receive
or store the private key.

Use `ens_elixir` when a product needs to read ENS state, prove that an ENS name
points at an agent, or prepare the next wallet approval for ENS or ERC-8004.

Use `xmtp_elixir_sdk` when a product needs chat identity, room membership,
message sync, or a room panel for Phoenix UI code. Product apps still own room
policy, moderation, persistence, and user-facing copy.

Use `agent_world` when a product needs AgentKit or AgentBook evidence. The
package returns evidence; the product decides what that evidence allows.

Use `regent_cache` for bounded, safe read caches. Do not use it as the owner of
workflow state, permissions, balances, ownership, or revenue data.

Use `railgun_elixir` when a server process needs Railgun shield, private
transfer, unshield, balance, or broadcast behavior. Use `kohaku_provider` for
the Ethereum JSON-RPC connection it runs against, and `kohaku_plugins` for the
host-side storage, key derivation, and asset shapes shared by Kohaku packages.

## Source-Of-Truth Rules

- Product HTTP behavior starts in the owning OpenAPI YAML file.
- Shipped CLI behavior starts in the owning CLI YAML file.
- Product databases own product workflow state.
- Onchain state owns balances, ownership, staking, and revenue distribution.
- Shared SIWA proves request identity and audience; product apps still decide
  whether the verified identity may perform the product action.
- XMTP inbox identity may be shared, but room meaning stays product-owned.

## Working Locally

Run package commands from the package folder:

```bash
cd /Users/sean/Documents/regent/elixir-utils/xmtp
mix deps.get
mix test
```

For the Kohaku packages:

```bash
cd /Users/sean/Documents/regent/elixir-utils/kohaku/plugins
mix test

cd /Users/sean/Documents/regent/elixir-utils/kohaku/provider
mix test

cd /Users/sean/Documents/regent/elixir-utils/kohaku/railgun
mix test
```

For the SIWA umbrella:

```bash
cd /Users/sean/Documents/regent/elixir-utils/siwa/siwa-elixir
mix test
```

Packages that depend on `siwa` use the local checkout during normal
development. When building or publishing those packages against Hex, set
`SIWA_HEX_PUBLISH=1`:

```bash
cd /Users/sean/Documents/regent/elixir-utils/ens
SIWA_HEX_PUBLISH=1 mix deps.get
SIWA_HEX_PUBLISH=1 mix hex.build
```

## Publishing Order

Publish `siwa` first. Then publish the packages that depend on it:
`siwa_keyring`, `ens_elixir`, and `agent_world`.

`regent_cache` and `xmtp_elixir_sdk` can be published independently.

```bash
cd /Users/sean/Documents/regent/elixir-utils/siwa/siwa-elixir/apps/siwa
mix hex.publish package

cd /Users/sean/Documents/regent/elixir-utils/siwa/siwa-elixir/apps/siwa_keyring
SIWA_HEX_PUBLISH=1 mix hex.publish package

cd /Users/sean/Documents/regent/elixir-utils/ens
SIWA_HEX_PUBLISH=1 mix hex.publish package

cd /Users/sean/Documents/regent/elixir-utils/world/agentbook
SIWA_HEX_PUBLISH=1 mix hex.publish package

cd /Users/sean/Documents/regent/elixir-utils/cache
mix hex.publish package

cd /Users/sean/Documents/regent/elixir-utils/xmtp
mix hex.publish package
```

## Current Package Versions

```bash
for d in \
  siwa/siwa-elixir/apps/siwa \
  siwa/siwa-elixir/apps/siwa_keyring \
  ens \
  world/agentbook \
  cache \
  xmtp \
  kohaku/plugins \
  kohaku/provider \
  kohaku/railgun
do
  printf "\n== %s ==\n" "$d"
  (cd "$d" && mix run --no-start -e 'IO.puts("#{Mix.Project.config()[:app]} #{Mix.Project.config()[:version]}")')
done
```

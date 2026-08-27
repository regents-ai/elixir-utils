# Regent Elixir Utilities

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![Elixir 1.19.5](https://img.shields.io/badge/elixir-1.19.5-lightgrey)](https://elixir-lang.org)
[![OTP 28](https://img.shields.io/badge/otp-28-lightgrey)](https://www.erlang.org)
[![Hex: 6 published](https://img.shields.io/badge/hex-6%20published-lightgrey)](https://hex.pm)

This repository holds the shared Elixir packages used by Regent services and Phoenix apps,
maintained by Regents Labs. Six of them are published on Hex; the rest are used from this
checkout as path dependencies.

Each package has one job. Product apps decide what a feature means for users; these packages
provide the reusable identity, messaging, signing, trust, formatting, and cache tools behind
those features.

> [!IMPORTANT]
> These are libraries, not services. Nothing here runs on its own, owns product state, or
> decides what a verified identity is allowed to do. Techtree proof and Fold policy are
> Techtree product records: shared SIWA and the utility packages prove identity or supply
> helper evidence, and never decide benchmark proof status or Fold reward eligibility.

## Where this sits

```text
  client surfaces
    ios                               mobile app, wallet, action signing
    regents-cli                       operator control surface
    regents-techtree-hermes-plugin    Hermes mission-control tab
                    │
                    ▼
  platform
    ash-platform                      Phoenix, LiveView, Ash: web, API, product domains
                    │
                    ▼
  services and chain
    siwa-server                       agent request signing, nonce and replay state
    media-web                         hosted card images and video
    fly-sentinel                      operator health checks
    regent-contracts                  canonical Solidity, ABIs, deployment records
    autolaunch-contracts              frozen Autolaunch V1 Solidity

  shared libraries and standalone tools
    elixir-utils                      SIWA, ENS, XMTP, cache, Credo checks   ◀ this repository
    design-system                     tokens and regent_ui components
    python-cli                        offline Techtree skill-tree inspection
    videocontrol                      video project and timeline workflows
```

## Packages

| Folder | Package | On Hex | Use it for |
| --- | --- | --- | --- |
| `siwa/siwa-elixir/apps/siwa` | `siwa` | `0.1.1` | Agent sign-in messages, nonces, receipts, signed request checks, wallet action envelopes, Ethereum helpers, and payment header parsing. |
| `siwa/siwa-elixir/apps/siwa_keyring` | `siwa_keyring` | `0.1.1` | Isolated local wallet creation and signing behind an internal HMAC-protected service. |
| `ens` | `ens_elixir` | `0.1.1` | ENS name reads, ENSIP-25 verification, ERC-8004 registration helpers, link planning, and wallet-ready unsigned ENS requests. |
| `xmtp` | `xmtp_elixir_sdk` | `0.1.2` | XMTP client lifecycle, conversations, groups, messages, sync helpers, product-scoped room panels, identity setup, resolver caching, and room metadata. |
| `world/agentbook` | `agent_world` | `0.1.0` | AgentKit header parsing, AgentBook lookup, World proof registration sessions, and wallet-ready AgentBook registration requests. |
| `cache` | `regent_cache` | `0.1.0` | Cachex-backed JSON values, strings, counters, sets, health checks, and cache child specs. |
| `credo_ash` | `credo_ash` | not published | Credo checks for Ash Framework anti-patterns, which generic Elixir linters cannot see. |
| `format` | `regent_format` | not published | Null-safe display values, `0x` address and hash truncation, decimal and currency rendering, timestamps, identity monograms. |
| `http` | `regent_http` | not published | Shared Req client conventions: default timeouts, request telemetry, and secret redaction in formatted errors. |
| `privy` | `regent_privy` | not published | Privy identity-token verification: ES256 signature, issuer, audience, and time claims, plus normalized linked wallet addresses. |
| `kohaku/plugins` | `kohaku_plugins` | not published | Kohaku host, storage, keystore, asset, balance, and broadcaster primitives. |
| `kohaku/provider` | `kohaku_provider` | not published | Ethereum JSON-RPC reads, calls, receipts, transaction submission, and Anvil test helpers. |
| `kohaku/railgun` | `railgun_elixir` | not published | Railgun chain config, signers, syncing, balances, shield, transfer, unshield, and broadcast helpers. |

"On Hex" records the latest stable version published at the time of writing; treat hex.pm as
the authority.

## Where each package is used

| Package | Used in |
| --- | --- |
| `siwa` | The shared SIWA service, product APIs that verify signed agent or operator requests, CLI-backed service calls. |
| `siwa_keyring` | Shared SIWA deployments, internal signing sidecars, services that need a wallet without exposing private keys to the caller. |
| `ens_elixir` | Platform trust linking, Autolaunch trust follow-up, CLI ENS commands, anything that shows or prepares ENS identity work. |
| `xmtp_elixir_sdk` | Platform Regent rooms, Autolaunch launch and subject rooms, Techtree public, review, and research rooms, server-owned room workers. |
| `agent_world` | Product trust sessions, Autolaunch trust summaries, Platform identity checks, CLI trust-link commands. |
| `regent_cache` | Short-lived read projections in Platform, Autolaunch, Techtree, SIWA, and shared workers. |
| `credo_ash`, `regent_format`, `regent_http`, `regent_privy` | The Regent Phoenix applications, as path dependencies. |
| `kohaku_plugins`, `kohaku_provider`, `railgun_elixir` | Kohaku protocol packages, server-owned Railgun flows, and forked-chain tests. |

## Choosing the right package

Use `siwa` when the question is: who signed this Regent request, what audience was it for,
and is the receipt still valid?

Use `siwa_keyring` when a process needs a signing wallet but should not receive or store the
private key.

Use `ens_elixir` when a product needs to read ENS state, prove that an ENS name points at an
agent, or prepare the next wallet approval for ENS or ERC-8004.

Use `xmtp_elixir_sdk` when a product needs chat identity, room membership, message sync, or a
room panel for Phoenix UI code. Product apps still own room policy, moderation, persistence,
and user-facing copy.

Use `agent_world` when a product needs AgentKit or AgentBook evidence. The package returns
evidence; the product decides what that evidence allows.

Use `regent_cache` for bounded, safe read caches. Do not use it as the owner of workflow
state, permissions, balances, ownership, or revenue data.

Use `railgun_elixir` when a server process needs Railgun shield, private transfer, unshield,
balance, or broadcast behavior. Use `kohaku_provider` for the Ethereum JSON-RPC connection it
runs against, and `kohaku_plugins` for the host-side storage, key derivation, and asset shapes
shared by Kohaku packages.

## Source-of-truth rules

- Product HTTP behavior starts in the owning OpenAPI YAML file.
- Shipped CLI behavior starts in the owning CLI YAML file.
- Product databases own product workflow state.
- On-chain state owns balances, ownership, staking, and revenue distribution.
- Shared SIWA proves request identity and audience; product apps still decide whether the
  verified identity may perform the product action.
- XMTP inbox identity may be shared, but room meaning stays product-owned.

## Working locally

Run package commands from the package folder. All paths below are relative to the repository
root.

```bash
cd xmtp
mix deps.get
mix test
```

The SIWA umbrella is tested as a whole:

```bash
cd siwa/siwa-elixir
mix test
```

Packages that depend on `siwa` use the local checkout during normal development. When
building or publishing those packages against Hex, set `SIWA_HEX_PUBLISH=1`:

```bash
cd ens
SIWA_HEX_PUBLISH=1 mix deps.get
SIWA_HEX_PUBLISH=1 mix hex.build
```

## Checks

These must pass before a change is proposed. Run the one for the package you touched:

| Package folder | Command |
| --- | --- |
| `cache` | `mix test` |
| `credo_ash` | `mix check` |
| `ens` | `mix test` |
| `siwa/siwa-elixir` | `mix test` |
| `world/agentbook` | `mix test` |
| `xmtp` | `mix test` |

CI runs the `cache`, `ens`, `world/agentbook`, and `xmtp` package checks on every push to
`main` and on every pull request.

## Publishing

Publish `siwa` first, then the three packages that depend on it. The other two are
independent.

```text
  siwa 0.1.1                    publish first
    ├── siwa_keyring 0.1.1      then this, with SIWA_HEX_PUBLISH=1
    ├── ens_elixir 0.1.1        then this, with SIWA_HEX_PUBLISH=1
    └── agent_world 0.1.0       then this, with SIWA_HEX_PUBLISH=1

  regent_cache 0.1.0            independent, publish any time
  xmtp_elixir_sdk 0.1.2         independent, publish any time
```

> [!WARNING]
> `mix hex.publish` is irreversible: a published version can be retired, but its contents
> stay on hex.pm forever. Check the version, the files list, and that no secret has been
> pulled into the package before confirming.

```bash
cd siwa/siwa-elixir/apps/siwa
mix hex.publish package

cd siwa/siwa-elixir/apps/siwa_keyring
SIWA_HEX_PUBLISH=1 mix hex.publish package

cd ens
SIWA_HEX_PUBLISH=1 mix hex.publish package

cd world/agentbook
SIWA_HEX_PUBLISH=1 mix hex.publish package

cd cache
mix hex.publish package

cd xmtp
mix hex.publish package
```

## Current package versions

To read every version straight from the source rather than from this file:

```bash
for d in \
  siwa/siwa-elixir/apps/siwa \
  siwa/siwa-elixir/apps/siwa_keyring \
  ens \
  world/agentbook \
  cache \
  xmtp \
  credo_ash \
  format \
  http \
  privy \
  kohaku/plugins \
  kohaku/provider \
  kohaku/railgun
do
  printf "\n== %s ==\n" "$d"
  (cd "$d" && mix run --no-start -e 'IO.puts("#{Mix.Project.config()[:app]} #{Mix.Project.config()[:version]}")')
done
```

## The other repositories

| Repository | What it is | What it deliberately does not do |
| --- | --- | --- |
| `ash-platform` | The Phoenix, LiveView, and Ash application: public web pages, the HTTP API, product domains, human identity, billing, and the Techtree and Autolaunch product areas. | It does not hold Solidity source or user signing keys; wallet actions remain browser-signed. |
| `autolaunch-contracts` | A clean-room Solidity implementation of the founder-frozen Autolaunch V1 system, controlled by its own `SPEC.md`. | It authorises no deployment, signature, or value movement; the older Autolaunch code in `regent-contracts` is historical reference only. |
| `design-system` | The shared Regent visual language: the style guide, design tokens, logos, fonts, and the `regent_ui` Phoenix component library. | Shared components never own product workflow state, authorisation decisions, money movement, or product database behaviour. |
| `fly-sentinel` | A small Phoenix service that reports Fly.io observability and operator preview checks. | It observes and reports; it does not deploy, scale, or change any other application. |
| `ios` | The Expo and React Native mobile app: the mobile wallet, action signing, and mobile Regent records. | It consumes the platform HTTP contracts and owns no server-side product logic. |
| `media-web` | A standalone Phoenix service that serves hosted Regents card images and video files from `media.regents.sh`. | It only serves bytes over HTTP; it holds no identity, database, or product logic. |
| `python-cli` | The installable `regents-techtree` Python package, whose shipped surface is a deterministic offline inspection of one champion/challenger skill-tree pair. | It does not evaluate or execute an agent, and it makes no network calls once its locked dependencies are installed. |
| `regent-contracts` | The canonical home for Regent Solidity source, Foundry tests, deployment scripts, verified deployment records, ABIs, and the chain-contract manifest. | It holds no HTTP or CLI contracts, Ash resources, workflow logic, UI, or projection workers. |
| `regents-cli` | The operator control surface: the `regents` command line tool, its generated bindings, and its local runtime. | It drives the platform over published contracts and owns no product database or on-chain authority. |
| `regents-techtree-hermes-plugin` | The Hermes plugin that presents Techtree mission control across Forge, Techtree Verify, and Uplift. | It is presentation only: no second task store, no private Verify database, no identity model, no payment system, and no Hermes runtime of its own. |
| `siwa-server` | The shared Sign-In With Anything service for signed agent requests, nonce and replay state, and internal keyring endpoints. | It owns no product data or product authorization policy. |
| `videocontrol` | A separate product: video project workflows, timeline editing, preview rendering, and Codex plugin media control. | It shares the house style but no runtime, database, or contract with the Regent platform. |

## License

MIT — see [LICENSE](LICENSE).

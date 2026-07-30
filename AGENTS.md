<!-- BEGIN REGENT META GENERATED -->
## Repo Contract

Generated from `meta/stack.yaml` and repo `repo.yaml` files. Local notes may live outside this block.

- Repo contract: `elixir-utils/repo.yaml`
- Owner: `elixir-utils`
- Release group: `public_beta`
- Owned areas: `siwa_library`, `ens_library`, `xmtp_library`, `agentbook_helpers`.
- Change API or CLI behavior in the owning YAML contract before changing code.
- Use `bd` only for execution state: tickets, claims, blockers, dependencies, and closure evidence.
<!-- END REGENT META GENERATED -->
# Regent Elixir Utilities Agent Guide

This repo owns shared Elixir utilities used by Regent products. Each package keeps its own `mix.exs`, version, tests, and release path.

## Regent Dependency Skills

The Regent dependency skills are installed in `/Users/sean/Documents/regent/.agents/skills` and `/Users/sean/.codex/skills`. Open the matching skill before touching these areas:

- `shared-siwa`: `siwa/siwa-elixir`, SIWA messages, receipts, nonce/replay rules, signed HTTP envelopes, and keyring packages.
- `ens-agent-identity`: `ens/`, ENS reads, name normalization, ENSIP-25, ERC-8004 identity, and unsigned wallet-ready ENS actions.
- `xmtp-rooms`: `xmtp/`, XMTP client behavior, inbox identity, group IDs, room mirrors, message sync, and presence helpers.
- `agentbook-agentworld`: `world/agentbook`, AgentKit header parsing, AgentBook lookup/registration, and World ID trust evidence.
- `cachex-regent-cache`: `cache/`, `regent_cache`, cache key shape, TTLs, invalidation, and cached JSON.
- `observability-promex-sentry`: only when adding metrics, logs, health checks, or private-data redaction to a package.
- `crypto-auth-primitives`: use `/Users/sean/Documents/regent/docs/dependency-surfaces/crypto-auth-primitives.md` when touching hashing, signature recovery, token classes, raw-body verification, or PyCryptodome-adjacent helper behavior.

## Core Rules

- Shared packages own reusable behavior, not product routes, product pages, or product databases.
- Product authorization stays in the product after shared identity or helper code verifies evidence.
- Techtree proof and Fold policy are product records, not shared SIWA or utility package records.
- Keep package APIs small, explicit, and covered by tests in the package folder.
- Do not move secrets into shared utility packages.
- Never read `.env` files. `.env.example` is allowed.

## Dependency Surface Guides

- Shared SIWA: `/Users/sean/Documents/regent/docs/dependency-surfaces/shared-siwa.md`
- ENS and AgentBook identity proof: `/Users/sean/Documents/regent/docs/dependency-surfaces/identity-proof.md`
- XMTP room behavior: `/Users/sean/Documents/regent/docs/dependency-surfaces/xmtp-rooms.md`
- Cache helpers: `/Users/sean/Documents/regent/docs/dependency-surfaces/cache-and-workers.md`
- Crypto and auth primitives: `/Users/sean/Documents/regent/docs/dependency-surfaces/crypto-auth-primitives.md`
- Cross-repo map: `/Users/sean/Documents/regent/docs/shared-agent-dependency-map.md`

## Validation

Run checks from the package folder you change:

```bash
mix check
```

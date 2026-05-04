# Shared Elixir Utility Dependencies

Updated: 2026-04-30

This file maps the shared Elixir utility packages to the Regent dependency skills that should be opened before changing them.

## Package Map

| Package | Skill | Boundary |
| --- | --- | --- |
| `siwa/siwa-elixir` | `shared-siwa` | Owns reusable SIWA parsing, verification, receipt, signed-envelope, and keyring behavior. It does not own product authorization. |
| `ens/` | `ens-agent-identity` | Owns ENS reads, name normalization, ENSIP-25 support, ERC-8004 identity helpers, and unsigned wallet-ready actions. It does not submit wallet transactions. |
| `xmtp/` | `xmtp-rooms` | Owns reusable XMTP client behavior. Product rooms, moderation, retention, and workflow state stay in the product repos. |
| `world/agentbook` | `agentbook-agentworld` | Owns AgentKit header parsing, AgentBook lookup/registration helpers, and World ID evidence handling. Product trust sessions stay product-owned. |
| `cache/` | `cachex-regent-cache` | Owns shared cache helpers. Cache is downstream of product DB state and chain truth. |

## Rules

- Keep shared package APIs narrow and explicit.
- Product databases and product routes do not belong in `elixir-utils`.
- Shared utilities may verify evidence, prepare actions, or return structured helper results; products decide what those results authorize.
- Do not cache secrets, raw auth tokens, private keys, full receipts, or unbounded user JSON.
- Do not move product secrets into shared utilities.
- Run tests from the package folder that changed.


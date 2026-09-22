# Shared Elixir Utility Dependencies

This file records what each shared Elixir utility package owns, and where its boundary stops.

## Package Map

| Package | Boundary |
| --- | --- |
| `agent_access/` | Owns `Accept` negotiation, `Vary` merging, and recovery response formatting. Product routes and the documents they serve stay in the product repos. |
| `blog/` | Owns Markdown metadata validation, safe HTML, and compile-time catalogs. Blog routes stay in the products; presentation lives in `Regent.Blog` in the design system. |
| `credo_ash/` | Owns Credo checks for Ash anti-patterns. It runs in dev and test only and never ships in a release. |
| `ens/` | Owns ENS reads, name normalization, ENSIP-25 support, ERC-8004 identity helpers, verified primary names, and unsigned wallet-ready actions. It does not submit wallet transactions. |
| `format/` | Owns display formatting helpers. Product copy, CSS tone classes, and domain labels stay in the consuming app. |
| `http/` | Owns shared Req client conventions: timeouts, telemetry, and secret redaction. Endpoints and credentials stay in the consuming app. |
| `privy/` | Owns Privy identity-token verification. Each app passes its own Privy configuration; sessions and accounts stay product-owned. |
| `siwa/siwa-elixir` | Owns reusable SIWA parsing, verification, receipt, signed-envelope, and keyring behavior. It does not own product authorization. |

## Rules

- Keep shared package APIs narrow and explicit.
- Product databases and product routes do not belong in `elixir-utils`.
- Shared utilities may verify evidence, prepare actions, or return structured helper results; products decide what those results authorize.
- Do not cache secrets, raw auth tokens, private keys, full receipts, or unbounded user JSON.
- Do not move product secrets into shared utilities.
- Run tests from the package folder that changed.


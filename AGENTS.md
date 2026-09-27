<!-- BEGIN REPO CONTRACT -->
## Repo Contract

Repository ownership is documented below and in the local `repo.yaml`. Follow the workspace `regent-workflow` for execution.

- Repo contract: `elixir-utils/repo.yaml`
- Owner: `elixir-utils`
- Release group: `public_beta`
- Owned areas: `siwa_library`, `ens_library`, `xmtp_library`, `agentbook_helpers`.
- Change API or CLI behavior in the owning YAML contract before changing code.
- Hermes/Astra coordinates scoped Claude/Fable work; no ticket tracker is required.
<!-- END REPO CONTRACT -->
# Regent Elixir Utilities Agent Guide

This repo owns shared Elixir utilities used by Regent products. Each package keeps its own `mix.exs`, version, tests, and release path.

## Core Rules

- Shared packages own reusable behavior, not product routes, product pages, or product databases.
- Product authorization stays in the product after shared identity or helper code verifies evidence.
- Techtree proof and Fold policy are product records, not shared SIWA or utility package records.
- Keep package APIs small, explicit, and covered by tests in the package folder.
- Do not move secrets into shared utility packages.
- Never read `.env` files. `.env.example` is allowed.

## Validation

Run checks from the package folder you change:

```bash
mix check
```

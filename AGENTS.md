# Regent Elixir Utilities Agent Guide

Follow the workspace `regent-workflow` (Pairing or Claude-only mode); no ticket tracker.

This repo owns shared Elixir utilities used by Regent products. Each package keeps its own `mix.exs`, version, and checks. Apps use the packages from a local checkout as path dependencies.

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

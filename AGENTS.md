# Regent Elixir Utilities Agent Guide

Follow the workspace `regent-workflow` (Pairing or Claude-only mode); no ticket tracker.

This repo owns shared Elixir utilities used by Regent products. Each package keeps its own `mix.exs`, version, and checks. Apps use the packages from a local checkout as path dependencies.

`ash_components/` (agents, identity, payments) is owned by the ash-template lane and merges through this repo's integrator; see `ash_components/AGENTS.md`.

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

<!-- BEGIN REGENT ROLLOUT REVIEW -->
## Code Review Rules

### Human and agent guidance drift

For every code review, read `.agents/skills/rollout-guidance-check/SKILL.md` and assess the diff's guidance
impact, even when no prose files changed. Trace affected behavior into public docs,
product/developer Skills, human-to-agent prompts, tooltips and other UI copy,
WebMCP/MCP schemas and descriptions, CLI help/errors/examples, OpenAPI, manifests
and generated or bundled copies. Shared behavior starts in ash-template and its
libraries; inspect affected consumers when available.

Report concrete mismatches introduced or made relevant by this change, with the
failing user/agent action and exact source locations. Distinguish source, packaged,
published and deployed versions; name missing cross-repository or live evidence.
Preserve dated history and avoid cosmetic findings. Do not inflate severity or
claim that no findings proves complete coverage. This is read-only review: never
sign, pay, activate earnings, publish or deploy to test an instruction.
<!-- END REGENT ROLLOUT REVIEW -->

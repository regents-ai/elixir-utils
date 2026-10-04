# Regent Elixir Utilities

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![Elixir 1.19.5](https://img.shields.io/badge/elixir-1.19.5-lightgrey)](https://elixir-lang.org)
[![OTP 28](https://img.shields.io/badge/otp-28-lightgrey)](https://www.erlang.org)

This repository holds the shared Elixir packages used by the Regent Phoenix apps and the shared
SIWA service, maintained by Regents Labs. Apps use every package from a local checkout of this
repository as a path dependency.

Each package has one job. Product apps decide what a feature means for users; these packages
provide the reusable identity, signing, wallet-step, formatting, HTTP, content, and lint tools behind those
features.

> [!IMPORTANT]
> These are libraries, not services. Nothing here runs on its own, owns product state, or
> decides what a verified identity is allowed to do. Techtree proof and Fold policy are
> Techtree product records: shared SIWA and the utility packages prove identity or supply
> helper evidence, and never decide benchmark proof status or Fold reward eligibility.

## Where this sits

```text
  product apps (repos/<app>/platform)
    regents  autolaunch  patchbay  techtree  ash-template  keyfleet
                    │
                    ▼
  shared service
    siwa-server                       agent request signing, nonce and replay state
                    │
                    ▼
  shared libraries
    elixir-utils                      ◀ this repository
    design-system                     tokens and regent_ui components
```

## Packages

| Folder | Package | Use it for |
| --- | --- | --- |
| [`agent_access`](agent_access/README.md) | `regent_agent_access` | `Accept` negotiation, `Vary` merging, Markdown or JSON recovery responses for public documents served to people and agents, and IETF rate-limit headers. |
| [`blog`](blog/README.md) | `regent_blog` | Repository-owned Markdown catalogs, safe HTML, stable contents links and local LaTeX assets. Presentation lives in `Regent.Blog` in the design system. |
| [`chain`](chain/README.md) | `regent_chain` | Wallet steps built on the server: checked addresses, contract calldata, the review a wallet button sends, and the check of a sent step. |
| [`credo_ash`](credo_ash/README.md) | `credo_ash` | Credo checks for Ash Framework anti-patterns, which generic Elixir linters cannot see. |
| [`ens`](ens/README.md) | `ens_elixir` | ENS name reads, ENSIP-25 verification, ERC-8004 registration helpers, link planning, verified primary names, and wallet-ready unsigned ENS requests. |
| [`format`](format/README.md) | `regent_format` | Null-safe display values, `0x` address and hash truncation, decimal and currency rendering, timestamps, identity monograms. |
| [`http`](http/README.md) | `regent_http` | Shared Req client conventions: default timeouts, request telemetry, and secret redaction in formatted errors. |
| [`jev`](jev/README.md) | `regent_jev` | Typed choice questions to Jev, the decision model on OpenRouter, each answer with the tokens it used and its cost in US dollars. |
| [`openai`](openai/README.md) | `regent_openai` | OpenAI text and screenshot replies, push-to-talk transcription and speech, each with the tokens it used and its cost in US dollars. |
| [`privy`](privy/README.md) | `regent_privy` | Privy identity-token verification: ES256 signature, issuer, audience, and time claims, plus normalized linked wallet addresses. |
| [`siwa/siwa-elixir/apps/siwa`](siwa/siwa-elixir/apps/siwa/README.md) | `siwa` | Agent sign-in messages, nonces, receipts, signed request checks, wallet action envelopes, Ethereum helpers, and payment header parsing. |
| [`siwa/siwa-elixir/apps/siwa_keyring`](siwa/siwa-elixir/apps/siwa_keyring/README.md) | `siwa_keyring` | Isolated local wallet creation and signing behind an internal HMAC-protected service. |

## Where each package is used

| Package | Used in |
| --- | --- |
| `regent_agent_access` | regents, ash-template, keyfleet |
| `regent_blog` | regents, autolaunch, patchbay, techtree |
| `regent_chain` | not used yet; planned for autolaunch, regents and keyfleet |
| `credo_ash` | regents, autolaunch, patchbay, ash-template, keyfleet (dev and test only) |
| `ens_elixir` | regents |
| `regent_format` | not used yet; planned for the product apps |
| `regent_http` | not used yet; planned for the product apps |
| `regent_jev` | ash-template (planned for patchbay) |
| `regent_openai` | not used yet; planned for patchbay |
| `regent_privy` | regents (platform and identity), autolaunch, patchbay, techtree, ash-template, keyfleet |
| `siwa` | siwa-server, patchbay, keyfleet, and `ens_elixir` in this repository |
| `siwa_keyring` | siwa-server |

## Choosing the right package

Use `siwa` when the question is: who signed this Regent request, what audience was it for,
and is the receipt still valid?

Use `siwa_keyring` when a process needs a signing wallet but should not receive or store the
private key.

Use `ens_elixir` when a product needs to read ENS state, prove that an ENS name points at an
agent, show a wallet's verified primary name, or prepare the next wallet approval for ENS or
ERC-8004.

Use `regent_chain` when a wallet button needs its steps built on the server, or the server
needs to check what a sent transaction did.

Use `regent_jev` when a product needs a model to pick one of a fixed set of answers about some
content (a label, a kind, a next step) and needs to know what each call cost.

Use `regent_openai` when a product asks an OpenAI model for a reply, a transcript or speech and
needs to know what each call cost.

Use `regent_privy` when a product signs people in with Privy and needs verified claims and
linked wallets.

Use `regent_agent_access` when a public page should answer both people and agents at the same
address.

## Source-of-truth rules

- Product HTTP behavior starts in the owning OpenAPI YAML file.
- Shipped CLI behavior starts in the owning CLI YAML file.
- Product databases own product workflow state.
- On-chain state owns balances, ownership, staking, and revenue distribution.
- Shared SIWA proves request identity and audience; product apps still decide whether the
  verified identity may perform the product action.

## Working locally

Run package commands from the package folder. All paths below are relative to the repository
root.

```bash
cd ens
mix deps.get
mix check
```

The SIWA umbrella is checked as a whole:

```bash
cd siwa/siwa-elixir
mix deps.get
mix check
```

`ens` depends on `siwa` from this checkout as a path dependency.

## Checks

These must pass before a change is proposed. Run the one for the package you touched:

| Package folder | Command |
| --- | --- |
| `agent_access` | `mix check` |
| `blog` | `mix check` |
| `chain` | `mix check` |
| `credo_ash` | `mix check` |
| `ens` | `mix check` |
| `format` | `mix check` |
| `http` | `mix check` |
| `jev` | `mix check` |
| `openai` | `mix check` |
| `privy` | `mix check` |
| `siwa/siwa-elixir` | `mix check` |

There are no GitHub Actions; run `mix check` locally for every package you touched. The shared services contract lives in `siwa-server`, which checks it against
its routes and the `siwa_keyring` router.

## Current package versions

To read every version straight from the source rather than from this file:

```bash
for d in \
  agent_access \
  blog \
  chain \
  credo_ash \
  ens \
  format \
  http \
  jev \
  openai \
  privy \
  siwa/siwa-elixir/apps/siwa \
  siwa/siwa-elixir/apps/siwa_keyring
do
  printf "\n== %s ==\n" "$d"
  (cd "$d" && mix run --no-start -e 'IO.puts("#{Mix.Project.config()[:app]} #{Mix.Project.config()[:version]}")')
done
```

## License

MIT — see [LICENSE](LICENSE).

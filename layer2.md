<!-- BEGIN REGENT META GENERATED -->
## Layer 2 Generated View

Generated from `meta/stack.yaml` and repo `repo.yaml` files. Local notes may live outside this block.

- Owner: `elixir-utils`
- Release group: `public_beta`
- Required for public beta: `true`
- Owned areas: `siwa_library`, `ens_library`, `xmtp_library`, `agentbook_helpers`.

Contracts:
- No contracts listed.

Acceptance checks:
- `elixir-utils/cache`: `mix test`
- `elixir-utils/ens`: `mix test`
- `elixir-utils/siwa/siwa-elixir`: `mix test`
- `elixir-utils/world/agentbook`: `mix test`
- `elixir-utils/xmtp`: `mix test`
<!-- END REGENT META GENERATED -->
# Elixir Utilities Layer 2

This file is the machine contract for `elixir-utils`.

## Purpose

This repo is the shared Elixir utilities workspace for Regent. It owns the reusable Elixir implementation for shared SIWA auth, ENS linking, XMTP messaging, and AgentBook or AgentKit support used by product repos.

## Canonical Identity

- Repo: `elixir-utils`
- Workspace role: shared Elixir libraries and service-side auth helpers
- Main package groups:
  - `siwa/siwa-elixir/apps/siwa`
  - `siwa/siwa-elixir/apps/siwa_keyring`
  - `ens`
  - `xmtp`
  - `world/agentbook`

## Owned Surface

- Shared SIWA library for message build and parse, nonce issue and verification, session verification, receipt issue and verification, authenticated request signing and verification, payment header parsing, and captcha support
- SIWA keyring service and client for isolated wallet creation plus message, raw payload, transaction, and authorization signing
- ENS library for verification, name reads, link planning, and wallet-ready unsigned requests for ENSIP-25, ERC-8004, reverse records, and subname work
- XMTP Elixir SDK for clients, conversations, groups, messages, preferences, sync, storage helpers, and the thin browser shim boundary
- AgentWorld library for AgentKit header parsing, signature verification, and AgentBook lookup or registration helpers

## Boundary And Non-Owned Surface

- This repo does not own any product route, page, browser flow, or CLI command surface
- The shared SIWA HTTP contract is defined in `/Users/sean/Documents/regent/regents-cli/docs/regent-services-contract.openapiv3.yaml`. This repo owns the Elixir implementation behind that contract, not the contract file itself.
- The ENS library does not ask for wallet approval or send chain transactions. The host app or signer does that work.
- The XMTP packages do not own product messaging rules, room policy, or browser wallet experience. The host app does.
- The AgentWorld package does not own the World App verification screen or product-level person and company records. The consuming product does.
- This repo does not define the production deployment topology for shared services. Host repos and operations layers decide where these libraries run.

## Source-Of-Truth Files

- `/Users/sean/Documents/regent/elixir-utils/README.md`
- `/Users/sean/Documents/regent/elixir-utils/siwa/siwa-elixir/README.md`
- `/Users/sean/Documents/regent/elixir-utils/ens/README.md`
- `/Users/sean/Documents/regent/elixir-utils/ens/USAGE.md`
- `/Users/sean/Documents/regent/elixir-utils/xmtp/README.md`
- `/Users/sean/Documents/regent/elixir-utils/world/agentbook/README.md`
- `/Users/sean/Documents/regent/elixir-utils/secret-allowlist.yaml`
- `/Users/sean/Documents/regent/regents-cli/docs/regent-services-contract.openapiv3.yaml`

## Inputs

- Host app calls from Regent products and shared services
- SIWA message fields, nonces, signatures, receipts, request envelopes, captcha input, and payment headers
- ENS names, chain ids, RPC URLs, registry addresses, agent ids, signer addresses, and resolver data
- XMTP identifiers, messages, group updates, consent changes, sync archive keys, and browser worker requests
- AgentBook or AgentKit headers, wallet addresses, registration payloads, and World proof outputs

## Outputs

- Verified SIWA sessions, receipts, parsed claims, and signed or verified authenticated request envelopes
- Isolated keyring wallet addresses plus message, raw payload, transaction, and authorization signatures
- ENS verification answers, read snapshots, link plans, and wallet-ready unsigned transaction requests
- XMTP client handles, conversation and group results, message results, consent state, archive helpers, and browser shim actions
- AgentBook lookup or registration payloads and verified AgentKit claims

## Persistent State

- The repo itself is not the source of truth for product data
- SIWA nonce state and replay protection live in whichever store the host app or deployment configures. This repo provides the memory and token replay store implementations.
- SIWA receipts depend on secrets supplied by the host deployment
- `siwa_keyring` can persist encrypted wallet material behind its own service store
- XMTP persistence, archives, and browser OPFS data live in the host runtime that embeds the SDK
- AgentBook lookup and registration results are consumed by host apps. This repo does not keep the product-level person or company records.

## Auth And Trust

- Shared SIWA semantics, receipt shape, and authenticated request rules are implemented here and consumed across products
- Key isolation is provided by `siwa_keyring` with HMAC-authenticated requests between the client and the keyring service
- ENS and AgentBook helpers verify external claims but do not become the final source of truth for product permissions on their own
- XMTP identities and browser wallet signatures remain under the host app's control

## Shared Identity And Action Boundaries

The SIWA utilities may build and parse SIWA messages, issue or verify nonces, issue or verify receipts, verify signed HTTP envelopes, and return verified wallet and agent claims. They may expose the verified token id as the current shared `agent_id` claim. Product repos own the mapping from that claim to local records such as Platform slugs, Autolaunch subjects, Techtree rooms, hosted runtimes, and mobile-linked Regent records.

The libraries may help prepare, register, verify, or mirror money-related actions for a host app. Value transfer still requires a user, operator, agent, or contract signature outside the shared utility boundary.

Interaction-safety support in this repo is reusable only: signed HTTP verification, keyring request authentication, signing helpers, message parsing, external claim verification, and SDK boundaries. Terminal approvals, external content ingestion decisions, tool-use approvals, and product action policy belong to the host app or CLI.

XMTP and chat room policy remains app-defined by default. This repo may provide clients, message helpers, sync helpers, and browser boundaries, but it does not own room creation, membership, moderation, retention, or product chat rules.

## External Dependencies

- Ethereum or Base-family JSON-RPC for ENS and identity work
- XMTP network and browser features such as workers and OPFS when the browser shim is used
- World and AgentBook services for proof lookup and registration
- Host product repos that mount these packages into HTTP, CLI, Phoenix, or worker surfaces

## Secret Boundary

- Deployments using this repo may hold SIWA nonce and receipt secrets, keyring HMAC secrets, isolated wallet keys, and any RPC or XMTP credentials needed by the host
- This repo should not hold product billing secrets, launch deploy keys, mobile payment secrets, or website session secrets unless a consuming product injects them at runtime
- `/Users/sean/Documents/regent/elixir-utils/secret-allowlist.yaml` is the machine-readable allowlist for shared utility env names and secret classes. New env names or secret classes must be added there before shared packages, docs, examples, or tests start using them.

## Acceptance Checks

- The SIWA library can issue a nonce, verify a signature, return a receipt, and verify authenticated request envelopes
- `siwa_keyring` can create a wallet and sign messages, raw payloads, transactions, and authorizations
- `ens_elixir` can verify, read, plan, and prepare unsigned requests for ENS and ERC-8004 flows
- `xmtp_elixir_sdk` can create clients, send and read messages, manage groups, and move sync archives
- `agent_world` can parse AgentKit headers and support lookup or registration helpers

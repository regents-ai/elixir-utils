# Elixir Utilities Layer 3

This file is the finished repo-local code atlas for `elixir-utils`. It covers the shared SIWA umbrella, the isolated keyring service, the ENS helper package, the XMTP Elixir SDK, and the AgentBook and AgentWorld helpers under `world/agentbook`. It also points at the tests and generated docs that prove each package behavior.

## Repo Shape

| Path | What lives there |
| --- | --- |
| `/Users/sean/Documents/regent/elixir-utils/siwa/siwa-elixir` | Umbrella app for shared SIWA libraries. |
| `/Users/sean/Documents/regent/elixir-utils/ens` | `ens_elixir` package. |
| `/Users/sean/Documents/regent/elixir-utils/xmtp` | `xmtp_elixir_sdk` package plus browser shim and generated docs. |
| `/Users/sean/Documents/regent/elixir-utils/world/agentbook` | `agent_world` package for AgentBook and AgentKit helpers. |
| `/Users/sean/Documents/regent/elixir-utils/README.md` | Top-level explanation that this repo tracks multiple packages, each with its own `mix.exs`. |

## SIWA Umbrella

### Umbrella structure

| Path | Role |
| --- | --- |
| `siwa/siwa-elixir/apps/siwa` | Main SIWA library used by Regent services and Phoenix apps. |
| `siwa/siwa-elixir/apps/siwa_keyring` | Isolated keyring app with local keystore, HTTP router, and signing service. |
| `siwa/siwa-elixir/fixtures` | Fixture material for SIWA tests and examples. |
| `siwa/siwa-elixir/harness` | Harness notes and end-to-end runner scaffolding. |

### `apps/siwa`

`apps/siwa/lib/siwa.ex` is the public entrypoint. It delegates the package surface to:

- `Siwa.Message` for message build and parse
- `Siwa.Nonce` for nonce issue, consume, and token helpers
- `Siwa.Verify` for message verification
- `Siwa.Receipt` for receipt creation and verification
- `Siwa.RequestAuth` for signed HTTP request creation and verification

Important module clusters inside `apps/siwa/lib/siwa`:

| File | Role |
| --- | --- |
| `message.ex` | Canonical SIWA message build and parse logic. |
| `nonce.ex` plus `nonce/memory_store.ex` and `nonce/token_replay_store.ex` | Nonce issue, storage, and replay prevention. |
| `receipt.ex` | Signed SIWA receipt creation and verification. |
| `verify.ex` | Signature verification and message checks. |
| `request_auth.ex` plus `request_auth/replay_store.ex` | Signed HTTP envelope creation and verification for follow-on authenticated requests. |
| `identity.ex` | SIWA identity helpers. |
| `crypto.ex` | Shared crypto helpers. |
| `signer.ex`, `local_signer.ex`, `remote_signer.ex`, `transaction_signer.ex` | Signing abstractions and signer backends. |
| `client_resolver.ex` and `registry.ex` | Resolver and client lookup support. |
| `captcha.ex` and `captcha_policy.ex` | Captcha-related gate logic. |
| `payment_gate.ex` and `x402.ex` | Payment-gate and x402 support. |
| `plug.ex` | Plug integration. |
| `tba.ex` | Token-bound account support. |
| `application.ex` | App supervision entrypoint. |

Boundary-crossing functions in this package:

- `Siwa.create_nonce/2` and `verify_nonce/2` cross into nonce storage
- `Siwa.verify/3` crosses into signature verification
- `Siwa.create_receipt/2` and `verify_receipt/2` cross into signed-token handling
- `Siwa.sign_authenticated_request/4` and `verify_authenticated_request/2` cross into HTTP-envelope auth

Tests for `apps/siwa`:

- `test/siwa/message_test.exs`
- `test/siwa/nonce_test.exs`
- `test/siwa/receipt_test.exs`
- `test/siwa/request_auth_test.exs`
- `test/siwa/usage_flow_test.exs`
- fixture tests for message, nonce, receipt, captcha, x402, and registry behavior
- `test/siwa/helper_usage_test.exs`

### `apps/siwa_keyring`

The keyring app is the isolation layer for wallet material.

| File | Role |
| --- | --- |
| `siwa_keyring/service.ex` | Main signing service. Creates wallets, checks wallet presence, reads the address, and signs messages, raw payloads, transactions, and authorizations by loading the signer from the keystore. |
| `siwa_keyring/keystore.ex` | Keystore read and write logic. |
| `siwa_keyring/auth.ex` | Auth support for keyring access. |
| `siwa_keyring/client.ex` | Elixir client for the keyring service. |
| `siwa_keyring/router.ex` | HTTP router for the service endpoints. |
| `siwa_keyring/proxy_signer.ex` | Proxy signer support used when the signer is remote from the caller. |
| `siwa_keyring/application.ex` | App supervision entrypoint. |

Boundary-crossing functions here are the signing calls in `SiwaKeyring.Service`:

- `create_wallet/1`
- `get_address/1`
- `sign_message/2`
- `sign_raw_message/2`
- `sign_transaction/2`
- `sign_authorization/2`

Tests for `apps/siwa_keyring`:

- `test/siwa_keyring_test.exs`
- `test/siwa_keyring/service_test.exs`
- `test/siwa_keyring/router_usage_test.exs`
- `test/siwa_keyring/fixture_keyring_test.exs`

## ENS Package

### Public surface

`ens/lib/agent_ens.ex` is the package entrypoint. It exposes the progression the README describes:

- `evm_record_key/3`
- `interoperable_address/2`
- `read_name/1`
- `plan_link/1`
- `verify/6`
- `verify_agent/5`
- `prepare_ensip25_update/1`
- `prepare_erc8004_update/1`
- `prepare_erc8004_clear/1`
- `prepare_bidirectional_link/1`
- Regent-specific helpers for reserved subname and ENSIP-25 updates

### Module atlas

| File | Role |
| --- | --- |
| `agent_ens/read.ex` | Reads ENS name state, resolver state, records, and ownership. |
| `agent_ens/plan.ex` | Builds the read-only link plan that explains what is done, missing, or blocked. |
| `agent_ens/verify.ex` | Verifies existing ENSIP-25 proof records. |
| `agent_ens/link.ex` | Prepares the unsigned requests for ENSIP-25 and ERC-8004 updates. |
| `agent_ens/tx.ex` | Low-level request builder for ENS, subname, reverse-name, and Regent-specific transactions. |
| `agent_ens/tx_request.ex` | Wallet-ready transaction request shape. |
| `agent_ens/record_key.ex` | ENSIP-25 record key generation. |
| `agent_ens/normalize.ex` | ENS and address normalization helpers. |
| `agent_ens/networks.ex` | Built-in network defaults. |
| `agent_ens/erc7930.ex` | Interoperable address formatting. |
| `agent_ens/erc8004/fetcher.ex`, `publisher.ex`, `registration.ex` | Reads and prepares ERC-8004 registration updates. |
| `agent_ens/internal/abi.ex`, `contract.ex`, `rpc.ex` | ABI constants, contract helpers, and RPC boundary. |
| `agent_ens/error.ex` | Canonical error shape returned by the package. |

Boundary-crossing functions:

- `read_name/1` crosses into ENS RPC reads
- `plan_link/1` crosses into both ENS and ERC-8004 state reads
- `prepare_ensip25_update/1` and `prepare_erc8004_update/1` cross into transaction building
- `prepare_bidirectional_link/1` is the package-level bridge between the two systems

Tests for `ens_elixir`:

- `test/record_key_test.exs`
- `test/normalize_test.exs`
- `test/read_test.exs`
- `test/verify_test.exs`
- `test/plan_test.exs`
- `test/tx_test.exs`
- `test/registration_test.exs`
- `test/erc7930_test.exs`

## AgentBook and AgentWorld Package

### Public surface

`world/agentbook/lib/agent_world.ex` is the entrypoint. It exposes:

- `parse_agentkit_header/1`
- `validate_agentkit_message/3`
- `verify_agentkit_signature/2`

### Module atlas

| File | Role |
| --- | --- |
| `agent_world/agentkit.ex` | Header parsing and AgentKit message validation and signature verification. |
| `agent_world/agent_book.ex` | AgentBook-specific reads and helpers. |
| `agent_world/registration.ex` | Registration request shaping and flow support. |
| `agent_world/tx_request.ex` | Wallet-ready transaction request shape. |
| `agent_world/networks.ex` | Network defaults for AgentBook calls. |
| `agent_world/internal/abi.ex` and `internal/rpc.ex` | ABI and RPC boundary helpers. |
| `agent_world/error.ex` | Canonical package error shape. |

Tests:

- `world/agentbook/test/agent_world_test.exs`

## XMTP Elixir SDK

### Public surface

`xmtp/lib/xmtp_elixir_sdk.ex` is the package entrypoint. It owns:

- runtime startup with `start_runtime/1`
- runtime handle creation with `runtime/1`
- client creation and build flows
- inbox id generation
- inbox lookup by identifier
- `can_message/2`
- metadata field helpers
- environment URL helpers
- safe-conversation conversion
- nanosecond-to-datetime conversion

### Main module clusters

| Cluster | Files | What they own |
| --- | --- | --- |
| Client lifecycle | `client.ex`, `clients.ex`, `installations.ex`, `signer.ex`, `inbox_id.ex`, `inbox_state.ex` | Client creation, registration, identity, inbox state, and installation handling. |
| Conversations and groups | `conversation.ex`, `conversations.ex`, `groups.ex` | DM and group creation, membership, admins, permissions, and metadata. |
| Messages and content | `messages.ex`, `content.ex`, `decoded_message.ex`, `codec.ex`, `codec_registry.ex` | Message sending, listing, decoding, and content codecs. |
| Preferences and sync | `preferences.ex`, `sync.ex`, `events.ex`, `metadata.ex` | Consent, inbox preferences, sync archives, and event handling. |
| Runtime internals | `runtime.ex`, `internal/registry.ex`, `internal/identity_server.ex`, `internal/conversation_server.ex`, `internal/sync_server.ex`, `internal/stats_server.ex`, `internal/names.ex` | Runtime supervision, process registry, and internal state servers. |
| Shared support | `constants.ex`, `types.ex`, `conversions.ex`, `date.ex`, `debug.ex`, `error.ex`, `storage.ex` | Type system, constants, conversions, storage, and debug helpers. |
| Browser shim | `browser_shim.ex`, `browser_shim/action.ex`, `browser_shim/async_stream.ex`, `browser_shim/opfs.ex` | Browser-only worker actions and browser-managed storage support. |

Boundary-crossing functions in the SDK:

- `start_runtime/1` enters the supervised runtime boundary
- `create_client/3` and `build_client/3` enter client registration and identity management
- `XmtpElixirSdk.Conversations` enters DM and group creation
- `XmtpElixirSdk.Messages` enters message send and read behavior
- `XmtpElixirSdk.Preferences` enters consent and inbox state
- `XmtpElixirSdk.Sync` enters archive export and import
- browser shim modules bridge the server package into browser-managed workers and OPFS storage

### Generated docs and browser shim

- `xmtp/doc/*` is generated API documentation for the package and is useful as a secondary atlas, but the source of truth remains `lib/`.
- `xmtp/browser_shim/src/*` and `xmtp/browser_shim/test/*` hold the browser-side support package that is not bundled into Hex as a runtime dependency.
- `lib/mix/tasks/compile.xmtp_compat.ex` is the custom compile task for compatibility artifacts.

Tests for `xmtp_elixir_sdk`:

- `test/clients_test.exs`
- `test/conversations_groups_test.exs`
- `test/messages_test.exs`
- `test/preferences_debug_sync_test.exs`
- `test/runtime_events_test.exs`
- `test/storage_test.exs`
- browser shim tests under `test/browser_shim/action_test.exs`, `async_stream_test.exs`, and `opfs_test.exs`

## Package Boundaries and Verification

- Each package keeps its own `mix.exs`, version, and publish path.
- `siwa/siwa-elixir` owns shared sign-in and key isolation behavior.
- `ens/` owns ENS and ERC-8004 planning and transaction preparation.
- `world/agentbook/` owns shared AgentBook and AgentKit helpers.
- `xmtp/` owns the XMTP Elixir SDK and browser shim.

The proof points are package-local:

- `mix test` inside `siwa/siwa-elixir`
- `mix test` inside `ens`
- `mix test` inside `world/agentbook`
- `mix test` inside `xmtp`

This repo is not one runnable app. It is one tracker for multiple shared libraries, each with its own public surface, tests, and release cycle.

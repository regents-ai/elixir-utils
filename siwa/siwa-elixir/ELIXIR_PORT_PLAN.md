# ELIXIR_PORT_PLAN.md — SIWA Elixir Port

## Summary

- Goal: replace the current Node SIWA sidecar with an Elixir-native SIWA library plus a separate Elixir signing service under `/Users/sean/Documents/regent/elixir-utils/siwa/siwa-elixir`.
- Scope: port the runtime surface from the JS repo, not just the sign-in message flow. That includes core sign-in, request signing, registry and reputation lookups, nonce stores, receipts, signer behavior, keyring signing, optional approval flow, CAPTCHA, token-bound account helpers, x402, client resolution, and the local test harness.
- Packaging default: use one main Elixir library and one separately shipped signing service in the same workspace. Keep the harness and fixtures in the repo, but not as public packages.
- Compatibility default: target behavior parity, not byte-for-byte wire parity. Regent can move to cleaner Elixir-native interfaces, but the security rules, outcomes, and end-to-end behavior must stay the same.
- Out of scope for the first cutover: the docs website and agent skill copy. Update those only after the runtime port is stable.

## Done means

- Every runtime feature currently exported by the JS SIWA package and the JS keyring proxy has a defined Elixir owner and acceptance test.
- The Elixir test harness can run the full real flow: create wallet, register or mock-register agent, sign in, issue receipt, and make an authenticated follow-up call.
- Regent can cut over to the Elixir implementation with no Node sidecar in the steady-state path.
- Any Regent HTTP or CLI changes caused by this port start in the YAML contract files before service or CLI implementation work begins.
- The final cutover removes old paths instead of keeping compatibility branches, shims, or duplicate flows.

## Public surface to port

- Core sign-in: message build, message parse, nonce issue, message sign, verification, result mapping, and receipt issue.
- Chain helpers: agent lookup, reputation lookup, registration payload build, registration send, built-in chain and contract address tables, metadata fetch, and agent registry string helpers.
- Request authentication: signed follow-up requests, request verification, replay protection, receipt attachment, and smart-wallet verification.
- Signer behavior: address lookup, message signing, raw signing for request authentication, transaction signing, local signer, proxy signer, and vendor-backed signers.
- Runtime extras: memory and durable nonce stores, reverse CAPTCHA, token-bound account helpers, x402 payment gate, client resolution, identity-file helpers, and Plug/Phoenix integration.
- Separate signing service: wallet creation, wallet presence check, address retrieval, message signing, transaction signing, authorization signing, encrypted key storage, audit logging, and optional approval gating.

## Implementation changes

- Create `/Users/sean/Documents/regent/elixir-utils/siwa/siwa-elixir` as a two-artifact workspace.
- Main artifact: `siwa`, the public Elixir library used directly by Regent services.
- Separate artifact: `siwa_keyring`, the isolated signing service plus Elixir client.
- Organize the main library by capability, not by copied JS filenames.
- Planned public modules: `Siwa.Message`, `Siwa.Nonce`, `Siwa.Verify`, `Siwa.Receipt`, `Siwa.Registry`, `Siwa.RequestAuth`, `Siwa.Captcha`, `Siwa.X402`, `Siwa.Identity`, `Siwa.ClientResolver`, `Siwa.TBA`, and `Siwa.Plug`.
- Planned behaviours: `Siwa.Signer`, `Siwa.TransactionSigner`, `Siwa.NonceStore`, `Siwa.CaptchaPolicy`, and `Siwa.PaymentGate`.
- Use a thin internal Ethereum layer instead of a broad all-purpose dependency. It must cover only what SIWA needs: message signing, address recovery, smart-wallet verification, contract call encoding and decoding, typed transaction signing, and JSON-RPC reads and writes.
- Keep both signing modes available. Regent should prefer direct in-process Elixir calls for verification and request signing. Use `siwa_keyring` only when key isolation is required.
- Treat the live JS source as the behavioral source of truth when the docs disagree.
- Freeze fixtures before porting the sensitive pieces. Required fixture sets: SIWA message strings, nonce issue and consume outcomes, receipt create and verify outcomes, signed GET and POST request cases, registry and reputation reads, keyring signing cases, keystore file cases, CAPTCHA retries, and x402 paid and unpaid flows.
- Resolve current JS inconsistencies during fixture freeze and then choose one clean Elixir path. Known mismatches already visible are the keyring HMAC payload format and drift window, and the encrypted keystore MAC behavior.
- Keep chain tables and enum sets as first-class Elixir data. The JS runtime currently exposes these service types: `web`, `A2A`, `MCP`, `OASF`, `ENS`, `DID`, `email`. It currently exposes these trust models: `reputation`, `crypto-economic`, `tee-attestation`.

## Delivery phases

1. Spec freeze from the JS repo and generate golden fixtures.
2. Port core message, nonce, receipt, and verification behavior.
3. Port chain, metadata, and registration behavior.
4. Port request signing, verification, and replay protection.
5. Port the signing service and its Elixir client.
6. Add Plug/Phoenix integration and switch Regent to the Elixir path.
7. Finish extras: CAPTCHA, TBA, x402, vendor-backed signers, and operational hardening.
8. Run shadow verification in Regent, make Elixir authoritative, and remove the Node sidecar.

## Test plan

- Golden fixture tests must compare Elixir results with JS outputs for message text, parse results, receipts, request signing, registry reads, keystore behavior, and error outcomes.
- End-to-end happy-path tests must cover local signing, keyring-backed signing, registration plus sign-in plus authenticated request, smart-wallet verification, CAPTCHA-protected sign-in, and x402-gated requests.
- Failure tests must cover wrong owner, wrong domain, wrong chain, expired nonce, reused nonce, expired receipt, replayed request, malformed message, missing required services, inactive agent, and failed reputation threshold.
- Signing-service tests must cover missing wallet, bad approval response, stale signing-service auth, bad signing-service auth, unlock failure, and restart recovery.
- Operational tests must cover parallel nonce races, replay races, clock skew, RPC failures, metadata fetch failures, and process restarts.

## Assumptions and defaults

- `siwa-elixir` starts from effectively empty project state and should be built fresh, not as a wrapper around the JS package.
- Regent is the main consumer, so Elixir-native interfaces are preferred over copying JS module shapes exactly.
- The first production cutover removes Node from Regent’s steady-state SIWA path.
- Vendor-backed signers remain in scope for the full port, but they must sit behind behaviours so the core library is not blocked by any one vendor.
- If this port changes Regent-visible nonce, verify, receipt, keyring, or CLI surfaces, update the YAML contracts first and then implement from those contracts.

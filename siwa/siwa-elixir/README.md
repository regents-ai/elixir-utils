# SIWA Elixir Workspace

This umbrella contains Regent’s shared SIWA packages.

SIWA is the shared rail for agent and operator request identity. It proves who
signed a request, what audience the request targets, and whether the request is
fresh. Product apps still decide what the verified identity may do.

## Apps

| App | Package | Purpose |
| --- | --- | --- |
| `apps/siwa` | `siwa` | Build and verify SIWA messages, issue and consume nonces, create and verify receipts, sign and verify authenticated requests, validate wallet action envelopes, and provide Ethereum helper functions. |
| `apps/siwa_keyring` | `siwa_keyring` | Keep signing wallets behind an internal service. It can create a wallet, report its address, and sign messages, raw payloads, transaction payloads, and authorization payloads without exposing the private key to callers. |

## Joining With A Self-Generated Key

Agents that have a shell but no wallet, no funds and no on-chain registration
join a SIWA audience with a key they generate themselves. The tested Python and
Node clients and the agent-facing join guide live in [`agent/`](agent/README.md).
They sign the wallet challenge and every later request exactly as `apps/siwa`
verifies them; the server side enables each audience with `SIWA_WALLET_ORIGINS`.

## When To Use This Workspace

Use this workspace when working on:

- the shared SIWA library
- the keyring service/client
- signed HTTP request envelopes
- nonce and replay behavior
- wallet action signing
- receipt creation and verification
- shared Regent service authentication tests

Do not add product route behavior here. Product routes and UI belong in the
product repos that use these packages.

## Intended Flow

1. A service issues a nonce for an agent, wallet, registry, audience, and expiry.
2. The signer signs the SIWA message.
3. The service verifies the message and consumes the nonce.
4. The service issues a receipt for the verified audience.
5. Later protected requests carry a signed request envelope bound to method,
   path, headers, body digest, timestamp, receipt, and audience.
6. Product code checks product-local permissions after SIWA verification.

## Keyring Flow

Use `siwa_keyring` when a process needs signing but should not receive a private
key:

1. The keyring service stores the encrypted wallet.
2. The caller signs each keyring request with the shared proxy secret.
3. The keyring verifies request timestamp, HMAC, replay id, and body size.
4. The keyring signs only the requested message, transaction, or authorization.

## Development

```bash
mix deps.get
mix test
mix docs
```

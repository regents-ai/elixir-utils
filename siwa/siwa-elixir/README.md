# SIWA Elixir

This workspace is the shared Elixir SIWA codebase for Regent services.

Use it as the shared implementation behind the shared SIWA contract in [`/Users/sean/Documents/regent/regents-cli/docs/regent-services-contract.openapiv3.yaml`](/Users/sean/Documents/regent/regents-cli/docs/regent-services-contract.openapiv3.yaml). Product repos may mount routes or adapters, but they should not present themselves as the owner of shared SIWA behavior.

## Apps

- `apps/siwa`: main SIWA library for Regent services and other Elixir consumers.
- `apps/siwa_keyring`: isolated signing service and Elixir client for cases that need key isolation.

## Support folders

- `fixtures/`: fixture definitions and golden-output placeholders.
- `harness/`: end-to-end flow notes and runner scaffolding.

## Intended flow

1. Issue a nonce for a registered agent.
2. Build and sign a SIWA message.
3. Verify the signed message and issue a receipt.
4. Use the receipt on later authenticated requests.
5. Keep private keys isolated behind the keyring service when needed.

The current Agent account shape is mandatory: wallet, chain, registry address,
token ID, audience, nonce, and the request body when a protected request has one.
When a request has a query string, the signed path includes that query string.
Receipt verification for protected requests must be called with the app audience
that owns the request.

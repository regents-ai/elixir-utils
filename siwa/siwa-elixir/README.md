# SIWA Elixir

This workspace contains the Elixir port of SIWA.

## Apps

- `apps/siwa`: main SIWA library for Regent services and other Elixir consumers.
- `apps/siwa_keyring`: isolated signing service and Elixir client.

## Support folders

- `fixtures/`: fixture definitions and golden-output placeholders.
- `harness/`: end-to-end flow notes and runner scaffolding.

## Intended flow

1. Issue a nonce for a registered agent.
2. Build and sign a SIWA message.
3. Verify the signed message and issue a receipt.
4. Use the receipt on later authenticated requests.
5. Keep private keys isolated behind the keyring service when needed.

# SIWA Elixir harness

This folder is reserved for end-to-end runner scripts and sample files.

## Target flow

1. Create wallet through `siwa_keyring`.
2. Register or mock-register an agent identity.
3. Ask the relying party for a nonce.
4. Sign a SIWA message.
5. Verify the message and receive a receipt.
6. Sign and verify an authenticated follow-up request.

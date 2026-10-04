# SIWA Elixir harness

This folder is reserved for end-to-end runner scripts and sample files.

## Target flow

1. Create wallet through `siwa_keyring`.
2. Ask the sign-in service for a wallet challenge.
3. Sign the challenge.
4. Receive a wallet receipt.
5. Sign and verify an authenticated follow-up request.

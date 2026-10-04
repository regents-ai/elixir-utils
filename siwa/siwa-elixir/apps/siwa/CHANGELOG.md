# Changelog

All notable changes to `siwa` should be recorded here.

## Unreleased

### Removed

- The registry-token sign-in. Wallet receipts (`siwa_wallet_receipt`) are now the
  one sign-in: `Siwa.Nonce`, `Siwa.Message`, `Siwa.Verify`, `Siwa.Registry`,
  `Siwa.AgentClaims`, `Siwa.Identity`, `Siwa.TBA`, `Siwa.Captcha` and their
  stores are gone, with `Siwa.create_nonce/2`, `Siwa.verify_nonce/2`,
  `Siwa.create_nonce_token/2`, `Siwa.verify_nonce_token/2`,
  `Siwa.sign_message/2`, `Siwa.verify/3` and `Siwa.Ethereum.owner_of/4`.
- Signed requests no longer carry `x-agent-registry-address` or
  `x-agent-token-id`.

### Changed

- `Siwa.required_authenticated_request_headers/1` and
  `Siwa.required_authenticated_request_components/2` describe the wallet
  request and take no kind argument.

## 0.1.1 - 2026-05-06

### Added

- Wallet action request helpers for transaction-signing flows.
- Ethereum personal-sign and RPC helpers for shared SIWA checks.

### Changed

- Nonces and request receipts now use stricter audience and timestamp handling.
- Request authentication now verifies the signed request before consuming replay state.

## 0.1.0 - 2026-04-22

### Added

- First Hex release for the shared SIWA library.
- Nonce, message, receipt, and request verification helpers for Regent SIWA flows.

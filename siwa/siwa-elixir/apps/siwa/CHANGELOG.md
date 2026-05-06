# Changelog

All notable changes to `siwa` should be recorded here.

## Unreleased

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

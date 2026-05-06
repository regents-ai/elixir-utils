# Changelog

All notable changes to `siwa_keyring` should be recorded here.

## Unreleased

## 0.1.1 - 2026-05-06

### Added

- Replay store support for keyring request authentication.
- Client and service helpers for signing wallet action requests.

### Changed

- Keyring requests keep raw request bodies for signature checks.
- Internal signing routes now use one canonical request shape.

### Security

- Hardened request signatures, timestamp handling, request size limits, and private-key isolation.

## 0.1.0 - 2026-04-22

### Added

- First Hex release for the isolated SIWA signing service and client library.
- Signing proxy, key storage, routing, and service helpers for Regent SIWA flows.

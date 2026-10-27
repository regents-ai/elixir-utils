# Changelog

All notable changes to `siwa_keyring` should be recorded here.

## Unreleased

## 0.2.0 - 2026-10-27

### Removed

- The HTTP signing routes (`SiwaKeyring.Router`), their HMAC headers (`SiwaKeyring.Auth`),
  replay store, remote client and proxy signer. Nothing called them, and they let a holder
  of one shared secret sign from the internet. The key store is used in-process only.
- The `:secret`, `:port`, `:host`, `:start_server` and `:replay_store` settings, and the
  application process that started the routes.

- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.

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

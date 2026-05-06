# Changelog

All notable changes to `ens_elixir` should be recorded here.

## Unreleased

## 0.1.1 - 2026-05-06

### Added

- Wallet-ready unsigned transaction request envelopes for ENS and ERC-8004 identity actions.
- ERC-8004 registration helpers and richer transaction request metadata.

### Changed

- ENS action preparation now preserves caller and network metadata in stable string-keyed shapes.
- Prepared action keys now produce consistent app-safe request data.

## 0.1.0 - 2026-04-22

### Added

- Standalone Hex package layout for `ens_elixir`, shaped for publishing and documentation.
- Elixir-first ENSIP-25 surface for record-key building, verification, link planning, and unsigned link preparation.
- Rich ENS read helpers for wrapped-name detection, resolver capabilities, addresses, content hashes, TTL, and requested text records.
- General ENS transaction helpers for records, addresses, resolver changes, TTL changes, and registry or wrapped subname actions.

### Changed

- Low-level Ethereum call helpers now live under an internal namespace instead of the public package surface.
- Package errors now use one structured error shape with explicit kind, message, and details.

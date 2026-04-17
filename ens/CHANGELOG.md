# Changelog

All notable changes to `ens_elixir` should be recorded here.

## Unreleased

### Added

- Standalone Hex package layout for `ens_elixir`, shaped for publishing and documentation.
- Elixir-first ENSIP-25 surface for record-key building, verification, link planning, and unsigned link preparation.

### Changed

- Low-level Ethereum call helpers now live under an internal namespace instead of the public package surface.
- Package errors now use one structured error shape with explicit kind, message, and details.

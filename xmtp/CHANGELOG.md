# Changelog

All notable changes to `xmtp_elixir_sdk` should be recorded here.

## Unreleased

### Added

- `Xmtp.add_remote_member/4` (and `Xmtp.Rooms.add_remote_member/4`): the room relay adds
  a member that owns its XMTP identity remotely (for example a CLI agent). The member's
  inbox id is taken from the principal or resolved from its wallet via the relay client;
  no server-side client is created for the member. Policy `allow_join` and capacity
  checks apply, and the membership row is recorded as joined.

## 0.1.2 - 2026-05-06

### Added

- Product-safe room primitives for identity, resolver, installations, room panels, metadata, sync, and room actions.
- Phoenix frontend agent guide for rendering shared room panels in host apps.

### Changed

- Wallet and inbox handling now normalizes addresses consistently across client and inbox helpers.
- Room server panels now use the shared room panel contract.

## 0.1.1 - 2026-04-22

### Changed

- Storage operations now classify filesystem failures as I/O errors.
- Preference update events now use typed updates for consent and HMAC changes.

### Security

- Streamed message content and stored archive data now reject malformed or hostile binary payloads safely instead of trying to load them directly.
- Group rule changes now follow the same permission checks as other group management actions, so ordinary members cannot lower group protections by changing rules directly.

### Fixed

- Archive listing now respects the requested age window correctly when filtering by day range.
- Unknown content types are now handled safely without growing permanent runtime state over time during filtering.

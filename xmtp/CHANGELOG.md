# Changelog

All notable changes to `xmtp_elixir_sdk` should be recorded here.

## Unreleased

### Security

- Streamed message content and stored archive data now reject malformed or hostile binary payloads safely instead of trying to load them directly.
- Group rule changes now follow the same permission checks as other group management actions, so ordinary members cannot lower group protections by changing rules directly.

### Fixed

- Archive listing now respects the requested age window correctly when filtering by day range.
- Unknown content types are now handled safely without growing permanent runtime state over time during filtering.

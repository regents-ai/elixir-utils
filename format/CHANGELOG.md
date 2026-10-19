# Changelog

## Unreleased

- `RegentFormat.Name.pattern/0` is the one rule for a name a person or an agent
  picks (founder, 2026-10-19): no control, line or paragraph separator, or
  format character, except a zero-width joiner or non-joiner between two visible
  characters and tag characters inside a complete flag. `regent_identity` and
  `regent_agents` use it.
- `short_relative_time/2` says the same as `relative_time/2` in a few letters,
  `"now"`, `"3m"`, `"2h"`, `"5d"`, `"2w"`, `"4mo"` or `"1y"`, for a narrow list.

## 0.2.0

- `short_address/1` is the one short form for an address, `0x1234..abcd`.
  It keeps `nil` as `nil` and shows other values as they are. `short_wallet/1`
  and the `empty` argument of `short_address/2` are gone: call
  `short_address/1`, and write `|| "..."` where a missing address needs words.
- `relative_time/2` says how far one moment is from another, `"3 minutes
  ago"` or `"in 2 hours"`, with `now` passed in.

## 0.1.0

- Initial release: display helpers, address/hash truncation, decimal and
  currency formatting, timestamp styles, and monograms promoted from
  `AutolaunchWeb.Format` and the autolaunch LiveViews.

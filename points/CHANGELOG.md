# Changelog

## 0.1.0 (unreleased)

- `RegentPoints.leaderboard/1`: the board a site reads once for every reader, under
  the system actor only. It answers the ten highest totals by public name, each with
  its account id, and `totals`, every positive total, highest first; highest total
  first, then the lowest account id. `RegentPoints.Leaderboard.place/2` gives a
  reader's place from their own total: one more than the totals strictly above it,
  so accounts level on points share a place; an account with none has no place. The
  site keeps the ids and totals on the server. Each site's accounts module adds
  `people/1`.
- Every award, correction and period bonus also broadcasts `points:board`, so a
  site's shared board reads again when any account's total moves.
- `RegentPoints.summary/1` also answers `earned_yesterday_micro`, `done` (how many
  times the account has done each listed action, today for a daily one) and each
  daily limit beside what is left of it. `Amount.format/1` drops a trailing ".00".
- What an account already has at the start earns its one-time points at the start:
  the account, linked X, GitHub and Farcaster accounts and the first paired agent, at
  most 80 points. `RegentPoints.StartAwards` runs from an hourly cron line on every
  site and asks each approved start rule's adapter for `existing(rule_id, starts_at)`;
  each reference goes through `record_event/2` and earns at the start time. Sean,
  6 November 2026.
- `StartAwards` reads the accounts that already have an event for a rule once per
  rule and leaves them out, so a later run offers nothing and costs one read per rule.
- Each catalog entry carries its version. A changed rule keeps its id and gets the
  next version; an account that earned a one-time rule never earns it again, and a
  daily rule's count carries across the change.
- The approved list is the one switch: `Rules.tracked/0` lists only approved rules
  with an adapter, so a site's Points page drops a stopped rule.
- The catalog no longer has `patchbay.first_report`, `patchbay.first_reply` or
  `autolaunch.first_launch`. The milestone catalog totals 250; 240 can be earned at
  launch, with `template.first_agent_note` not approved. Sean, 6 November 2026.
- The guide gives the daily limit the code applies: repeat actions and Credits
  bought earn at most 150 base Points a UTC day together (100 and 50). It said 200.
- The catalog no longer has `identity.ens_selected`, `keyfleet.integration.marimo` or
  `keyfleet.integration.ddocs`. The milestone catalog totals 290. Sean, 4 Nov 2026.
- `RegentPoints.TallyPeriods` emits `[:regent_points, :tally_periods, :finished]`
  at the end of every daily run, with the tallies it queued (`accounts`) and the
  ended `periods`, including a run with nothing to queue, so the owner site can
  export when the tally last ran.
- `RegentPoints.Amount.format/1` is exact at any size. It divided micro-Points
  by 1,000,000 with Decimal's 34-digit precision, so an amount longer than 34
  digits was rounded half up and a page could show more Points than there are
  ("100,000,…,000.00" for "99,999,…,999.99"). It now moves the decimal point six
  places, as `RegentFormat` does since its exact-at-any-size change.
- `RegentPoints.Amount.format/1` shows Points the one Regent way
  (`RegentFormat.amount/1`): "1,234.56", "0.400".
- `RegentPoints.WalletSnapshot.owner/2` answers the account holding a wallet at
  a moment, from the wallet history: `{:ok, account_id}`, or
  `{:error, :unknown_owner}` when no account or more than one held it then. A
  wallet removed earlier has no owner, and the current owner is never used.
  The package's tests now run on an isolated local database
  (`regent_points_test_local*`), created on first run.

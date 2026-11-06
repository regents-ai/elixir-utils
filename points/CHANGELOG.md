# Changelog

## 0.1.0 (unreleased)

- Spending earns Points (Sean, 6 November 2026): one point per dollar, at most 100
  dollars per account per UTC day, under its own `spending:account` limit beside the
  100 a day from actions. Four rules, each switched on by itself:
  `keyfleet.key_spend`, `patchbay.payment_spend`, `template.pinned_note_spend`,
  and `autolaunch.auction_bid_spend`; none is approved yet. Autolaunch token buys earn
  no dollar points.
  Their evidence names the payment (`usd_micros`, `payer`, `token`, `token_amount`,
  `token_decimals`, `price_usd`, `price_source`, `chain_id`, `block_number`, `tx_hash`,
  `log_index`), and `usd_micros` must equal
  `floor(token_amount × price_usd × 10^6 / 10^token_decimals)`. An award without all of
  them, or with another figure, is rejected as `invalid_spending_evidence`; one above
  10^15 as `spending_amount_too_large`; one reported by a site other than the app in the
  rule's id as `ineligible_spending_app`. A price has at most 30 digits each side of
  the dot. A payment counts on its block's UTC day and
  pays once whichever rule, site or account reports it, used by its first report even
  when clipped to nothing; a full take-back, or a 0 correction of a 0-point award that
  used it, frees it for the right account, reported again under
  `RegentPoints.source_after_take_back/2`. The holder
  bonus applies as to any points. `Rules.base_micro/2` takes the rule and the evidence.
  `RegentPoints.summary/1` also answers `dollars_today`. Migration `20261106172400` adds
  the `payment_once` check and one row per payment on `point_cap_usage`, and lets a
  correction be 0 only for a spending award, once per award (`entry_direction` and
  `point_entries_one_zero_correction_index`); no new column. It applies in one
  transaction and waits at most 5 seconds for a lock. Rolling it back is refused once a
  0 correction exists.
- Points no longer has a Credits rule (Sean, 6 November 2026): `credits.purchase_settled`,
  its `credits` category and 50-a-day limit, and the per-USDC rate are gone, so a rule
  snapshot's `daily_caps_micro` holds only `activity:account` and repeat actions earn
  at most 100 base Points a UTC day. `Rules.base_micro/1` takes the rule alone. Ledger
  entries no longer read or write `purchased_usdc_atomic`; the column leaves the
  `point_entries` table in a later shared change, once every site runs this version,
  because a site on an older version still reads it.
- `people/1` also answers each account's `wallet` and its `ens_name`, and `name` is
  `nil` when the site shows the wallet in place of a name; leaderboard rows carry
  both. Every wallet is public (Sean, 6 November 2026).
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

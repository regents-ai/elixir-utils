# Changelog

## 0.1.0 (unreleased)

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

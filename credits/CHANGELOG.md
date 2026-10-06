# Changelog

## 0.1.0 (unreleased)

First version of Regent Credits: one prepaid balance per Privy account,
shared by every Regent site.

- Double-entry ledger (`ash_double_entry`) in the `regent_credits` schema of
  the site's database, with the private currency `XRC` kept to six decimals.
  Ledger transfers cannot be changed or deleted.
- Holds: hold, give back, charge, carry over, settle, bounty payout and
  takeback, given Credits spent first and returned as the same kind.
- Agent spending limits: on or off, most per spend, daily limit, sites.
- Purchases with USDC on Base (approve and deposit into REGENT staking) and
  Ethereum (transfer to the Treasury Safe, counted after 12 blocks), checked by
  the page and by the site's Oban through an AshOban trigger. A person reports
  only payments from the wallets the site's sign-in verified for them.
- Admin gifts to Privy accounts or wallet addresses; address gifts attach when
  the wallet signs in.
- Refunds while an account has never used Credits, closed on the Treasury
  Safe's transfer back to the paying wallet.

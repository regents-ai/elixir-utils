# Changelog

## 0.1.0 (unreleased)

- `RegentCredits.Listener` listens on the site's own `Postgrex.Notifications`
  connection, named in the required `notifications:` setting, instead of opening
  one with the repository's settings. The site opens that connection on the
  database's direct address, so its repository can serve through the pooler, and
  Agents' listener shares it: one listening connection per machine, not two.
- Migration 20261026220000 installs ash_postgres's version 7 `public.ash_required`.
  Version 6, which the first Credits migration installs, runs with an empty search
  path and so cannot find `ash_raise_error`: a missing required value raised
  "function does not exist" instead of Ash's error. Without this, a fresh database
  got the broken copy back after the site's own fix.
- ash_postgres comes from Regent's copy of 2.15.2 (regents-ai/ash_postgres at
  cc886ab3), which carries ash-project/ash_postgres#910: upserts are written to the
  schema the site's repo picks, as on 2.13.0. It clears the two 2.13.0 advisories.
  Ash 3.37.2, ash_sql 0.8.4.
- Credits deposits on Base are read from the chain every five minutes instead of
  every minute, since each read is a paid node call on every site. A person's own
  Buy is still credited by its purchase check within a minute.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions. `RegentCredits.Deposits` drops an unused
  `require Ash.Query`; ash_oban 0.10.2.

First version of Regent Credits: one prepaid balance per Privy account,
shared by every Regent site.

- Double-entry ledger (`ash_double_entry`) in the `regent_credits` schema of
  the site's database, with the private currency `XRC` kept to six decimals.
  Ledger transfers cannot be changed or deleted.
- Holds: hold, give back, charge, carry over, settle, bounty payout and
  takeback, given Credits spent first and returned as the same kind.
  `lock_holds` locks every account a transaction closing several people's
  holds may move, once and in order, before it starts.
- Agent spending limits: on or off, most per spend, daily limit, sites. The
  daily limit counts a carried-over bid once, on the day it was first held.
- Purchases with USDC on Base (approve and deposit into REGENT staking) and
  Ethereum (transfer to the Treasury Safe, counted after 12 blocks), checked by
  the page and by the site's Oban through an AshOban trigger. A person reports
  only payments from the wallets the site's sign-in verified for them, and a
  report is saved only once the chain holds it as that purchase's Buy.
- Every Credits deposit on Base is read from the chain every five minutes and
  credited exactly as it landed, reported or not, so a paid Buy whose page
  closed is still credited. A deposit from a wallet no account holds goes to
  the account that reported it, or waits under the wallet until a sign-in
  shows that wallet or a report of it arrives. Each wallet's payment in a
  transaction is its own purchase, so two wallets paying in one transaction
  are credited separately. A purchase's check writes only while the purchase
  is still being checked, so it never undoes a deposit's credit. Wallets and
  transaction hashes are stored lowercase. Purchase and refund amounts are
  USDC to the millionth.
- Admin gifts to Privy accounts or wallet addresses. A gift or bounty to a
  wallet an account showed at its last sign-in lands on the account at once;
  to any other address it waits until a sign-in shows that wallet.
- Every balance change announces itself through the shared database;
  `RegentCredits.Listener` passes it to the site's PubSub on `topic/1`.
- Refunds while an account has never used Credits, closed on the Treasury
  Safe's transfer back to the paying wallet.
- Account history reads as what happened, not as ledger rows:
  `RegentCredits.history/2` answers one entry for each purchase, gift, refund,
  hold, return, spend and payment received, with a `kind`, a positive `amount`,
  a `direction` and the facts that apply. A hold's transfers are added
  together, and a page never ends inside one. The entries no longer carry
  `operation`, `available_delta` or `held_delta`.
  `RegentCredits.History.Words` holds the words every site shows for them,
  including the purpose `note_pin` ("Note pinned") for a note an agent pinned.
- A refund no longer asks whether the account has ever used Credits (Sean, 13
  October 2026: exceptions are decided case by case). `start_refund` takes a
  purchase's Credits out whenever that many purchased Credits are still in the
  account; the `:used` refusal is gone. Holds no longer write
  `regent_credits.first_uses` and nothing reads it. The table itself stays
  until every site that places holds runs this version, because an older
  version writes to it on every hold; a later migration removes it.
- `RegentCredits.history_of/2` answers one person's history to a Credits admin,
  the same entries the person reads. An entry for Credits set aside, returned
  or spent now carries `agent_address` and `pairing_id` when the person's agent
  set them aside.
- A site may say what led to a hold: `RegentCredits.hold/6` takes `tool` and
  `request`, kept on the hold (two new columns on `regent_credits.holds`, added
  by migration `20261013202732_hold_cause`, which must run before any site sends
  them) and shown on the history entry with the hold's `key`. A `request` over
  4,000 bytes, or one Postgres cannot store as text, is not kept and the hold
  is still placed. An agent is given
  `request` only on a hold it placed itself.
- Runs on Ash 3.36 and AshOban 0.10. Ash postgres stays at 2.13.0.
- Credits tells the site about purchases with Ash signals
  (`RegentCredits.Signals`): `:purchase_credited` when a purchase is credited
  to an account, and `:purchase_attributed` when a payment credited while it
  waited under its wallet goes to the account that signed in with that wallet.
  Both carry `purchase_id` and `privy_user_id` and are emitted in the credit's
  transaction. `RegentCredits.Credited` and the `on_credited` setting are gone:
  a site that pins this version removes its `on_credited` setting and its
  module, and listens to both signals instead. A checked purchase is credited
  by its own action, `:credit_checked`; `:finish` only records one that will
  not be credited.
- Holds have an index on the owner and the time they were held
  (`holds_privy_user_id_held_at_index`, built concurrently). An agent's spend
  today and a site's total for one agent read only that owner's holds instead
  of the whole ledger. Each site runs the new migration through
  `RegentCredits.Migrator.up/1` when it re-pins.

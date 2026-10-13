# Changelog

## 0.1.0 (unreleased)

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
- Every Credits deposit on Base is read from the chain once a minute and
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
  `RegentCredits.History.Words` holds the words every site shows for them.
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

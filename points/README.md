# Regent Points

Share one account-linked Points ledger across Regent sites. The package owns the
`regent_points` schema, rules, award calculations, corrections and NFT reads.
Each host supplies verified source facts, its account lookups, Repo, PubSub and
Oban instance. Including the package starts no server, worker loop or migration.

## Configure the host

```elixir
config :regent_points,
  repo: MySite.Repo,
  pubsub: MySite.PubSub,
  accounts: MySite.Points.Accounts,
  chain_client: MySite.ChainClient,
  ash_domains: [RegentPoints],
  program_id: "regents-points-v1",
  starts_at: nil,
  approved_rules: [],
  adapters: %{}
```

Earning is off while `starts_at` is `nil`. Setting it starts the program and its
30-day periods, and it never changes or returns to `nil` afterwards: awards still
being checked, corrections and bonuses all count periods from it. To stop earning
later, empty `approved_rules`.

The accounts module implements `RegentPoints.Accounts`: `human/1` supplies the
verified wallet set for a canonical integer account ID; `agent_names/2` returns names
only for agents belonging to that account, as `{:ok, names}`; `people/1` returns how
each listed account shows to other people, for the leaderboard: its name, or `nil` and
its wallet (every wallet is public), the wallet's ENS name, and its pictures. Return `{:error, reason}`
on lookup failure so the account page shows an error rather than a false missing-agent label. Agent `actor_id` is the verified paired
agent record ID. The shared `regent_names.platform_human_users` table must exist;
this package references it but never creates, updates or merges people.

The chain client implements `RegentPoints.ChainClient`: `rpc(%{chain_id: 8453}, method, params)`.
The page reads current Base holdings as a preview. Confirmation reads one saved
finalized block immediately before the end of the 30-day period, shared by every
account. The RPC must support `finalized`, historical block headers and EIP-1898
`eth_call` by canonical block hash. Verify those capabilities before enabling earning;
missing historical evidence retries rather than falling back to current holdings.

Add `points: 5` and `points_chain: 2` queues to the site's existing Oban instance.
Only Regents, the one tally owner, adds a daily cron for `RegentPoints.TallyPeriods`;
every other site leaves it out. Every site adds `{"@hourly", RegentPoints.StartAwards}`
for the start awards below. All hosts use the same shared database and schema.
Use the same Repo for source actions and Oban. The package's notifier broadcasts
on the configured host PubSub under `points:<account_id>` when that account's total
moves, and under `points:board` when any account's does; cross-node notification
delivery follows the host's PubSub topology.

`RegentPoints.leaderboard/1` is system-only. The site reads it once for every reader,
on `points:board` and on a schedule, and keeps the answer on the server: the ten
highest rows (`account_id`, `name`, `wallet`, `ens_name`, `squares`, `picture`, `rank`,
`points_micro`) and
`totals`, every positive total, highest first. A reader gets the rows without their
account ids, a mark on their own row, and their own place from
`RegentPoints.Leaderboard.place(totals, own_total)`, never the list of totals.

## Record committed actions

In the source action's transaction, call the system-only domain action:

```elixir
{:ok, _} =
  RegentPoints.record_event(%{
    rule_id: "patchbay.reply_published",
    source_app: "patchbay",
    source_kind: "reply",
    source_event_key: reply.id
  }, actor: %{role: :system})
```

Only those four reference fields enter the Oban job. No adapter, Points table or
chain read runs in the product transaction. The job is inserted in the source's own
transaction, so the action and its Points job commit or roll back together; an insert
failure raises and rolls back the action. Outside a transaction, the same API can
resubmit a reference to an already committed source. Never repeat a post or
wallet action to recover Points; reconcile from authoritative source records.

The background verifier calls the rule's configured adapter `verify(reference)`.
It must load authoritative persisted records, not trust browser assertions. Return
`{:ok, facts}`, `{:error, reason_atom}` for a permanent rejection, or
`{:retry, reason}` for an outage. Exceptions also retry through Oban. Invalid facts
and conflicting evidence get a permanent private `source_rejections` audit, without
changing an accepted event. Infrastructure failures retry; discarded Oban jobs need
operator diagnosis.

Facts have atom keys: `source_app`, `source_kind`, `source_event_key`, `account_id`,
`actor_kind` (`"human"` or `"agent"`), `actor_id`, `source_action_at`, `qualified_at`,
`evidence_ref` and `evidence`. Both times are UTC DateTimes. Freeze the beneficiary
at action time. Source identity must match the job.
Agent evidence contains `"attribution_link_id"`; Keyfleet additionally needs
`"key_id"` and `"ownership_epoch"`; social milestones need a stable
restricted `"subject_key"`. A spending rule's evidence names the one payment it is
for, every key required: `"usd_micros"` (the dollars, in millionths, a positive
integer), `"payer"` (the paying wallet's lowercase address), `"token"` (the paid
token's lowercase address), `"token_amount"` (its atomic amount as a digit string, at
most 78 digits), `"token_decimals"` (the token's decimals, 0 to 255), `"price_usd"`
(the dollar price of one whole token, a decimal string of at most 30 digits each
side of the dot, `"1"` at face value),
`"price_source"` (where the price came from: valid UTF-8 text of at most 200 bytes,
with no NUL byte), `"chain_id"`, `"block_number"`,
`"tx_hash"` (lowercase) and `"log_index"`. The award saves all of them. `"usd_micros"`
must equal `floor(token_amount × price_usd × 10^6 / 10^token_decimals)`, worked out
exactly in whole numbers, so every award can be checked from its own record; any
other figure is refused as `invalid_spending_evidence`, and one above 10^15 (a
billion dollars) as `spending_amount_too_large`. The site works out the dollars
before it reports; Points reads no price.

What a site reporting spending must do:

- `"log_index"` is the receipt's block-wide `logIndex` of the one event the rule
  names, never a position within the transaction.
- Each spending rule names exactly one event, so a payment has one log whichever
  rule reports it.
- `source_action_at` is the block's time from the block header, never the site's
  clock: the payment counts on its block's UTC day.
- A block time ahead of the server's clock is refused as
  `invalid_qualification_time`; the site reports that payment again once the time
  has passed.

Reports through WebMCP, HTTP, CLI, MCP or the site UI
must use the same business source identity for the same completed action. Transport
never establishes agent identity or creates a second award. One source id is one
award, so a payment freed by a take-back is reported again under a new source id,
`RegentPoints.source_after_take_back(source_event_key, correction_key)`: the
source id of the report being made again (the wrong account's own report, or the
right account's report that earned 0 as a repeat while the wrong account held the
payment) and the take-back's correction key. It is
`"after:" <> RegentPoints.Store.digest({source_event_key, correction_key})`, 70 bytes
however long either key is and however many take-backs came before. A site never
builds that id itself.

Every site that has pinned notes reports the template's rule
`template.pinned_note_spend` as `source_app: "template"`, the app in the rule's id, so
the source id carries the site's own name:
`RegentPoints.pinned_note_source(site_app, note_id)`, which is
`"pinned_note:" <> RegentPoints.Store.digest({site_app, note_id})` (76 bytes). Two
sites' note 42 are then two sources. A site never builds that id itself.

What an account already has at the start earns its one-time points at the start,
without the person doing anything: the account (`account.activated`), its linked X,
GitHub and Farcaster accounts (`social.*`) and its first paired agent
(`agent.activated`), at most 80 points (`RegentPoints.Rules.start_rules/0`). Sean,
6 November. `RegentPoints.StartAwards` asks each approved start rule's adapter for
`existing(rule_id, starts_at)`: one `{account_id, reference}` per account for state
that existed before the start and still holds (a pairing still paired, a link still
linked). It records each reference through `record_event/2`, so the adapter's
`verify/1` proves it as usual and reports the real time; Points earns it at the start
time. The milestone ids are the same as for new actions, so an account earns each once
whichever site records it. No other rule earns for anything before the start. A site
lists only the start rules it has a source for: Patchbay has no linked accounts, so it
lists the account and the first pairing.

## Rates and allowances

Repeat actions share one limit of 100 points per UTC day for the account and all its
paired agents, across every interface, with one count per action for the account
whoever acted. The actions add up
to more than 100 on purpose: the limit decides. One-time actions use no daily limit
and remain once per canonical account: one ledger entry, however many qualifying
actions arrive. Once the account has earned one, or while that award is still
being checked, a later qualifying action records no event and queues no award;
the check runs under the account's lock, so actions arriving together still earn
once. A repeat action over its limit still writes a 0-point entry that shows the
reduction. `RegentPoints.summary/1` lists only the daily allowances that a rule
earning now on this site counts against.

The repeat actions (Sean, 13 October) are: Autolaunch auction created 20 once a day,
auction bid 20 once a day, token trade through the site 10 once a day; Keyfleet key
bought 10 up to five a day; Patchbay Offer placed 5 up to ten a day, report published
10 once a day and reply published 5 once a day (Patchbay values, Sean, 14 October).
A Patchbay bid, starting or takeover, earns at the moment its Offer starts showing,
once for that bid; a bid that only leads and is then replaced earns nothing. Staking
an Autolaunch token earns 40 once per account. Regents staking, Techtree, the first
use of a site, and Patchbay's accepted solution and resolved report earn nothing.
There is no active-day or recurring vote rule; Keyfleet retains its 10-point
first-vote milestone. Every Patchbay report and reply must be accepted by Patchbay's
own quality check before it is published and earns; that check is Patchbay's, not
this package's.
Once Points has started, a rule that has ever earned is never removed from the
catalog: the points it awarded are still read against it. A rule's id never changes:
a changed rule keeps its id and gets the next version in the catalog, so what an
account earned under the old version still counts against the new one, and each
ledger entry keeps the version it earned under. A new id is only for a new action. To
stop a rule, take it off `approved_rules`.
Two approved candidates stay out of the catalog until their products exist (Sean, 8
October): Keyfleet rollcall, 5 once/day, and independently verified Patchbay repair, 15
twice/day. All rules remain operationally disabled in the template.

Spending earns one point per dollar, at most 100 dollars per account per UTC day
(Sean, 6 November 2026), beside the action's fixed points and under its own
limit, `spending:account`: one account can earn 100 points a day from actions and 100
more from dollars. The account, all its wallets and all its paired agents share the
100 dollars, on every site. A payment that crosses the limit earns only what is left of
the day, and the rest of that day earns nothing. One point per dollar is fixed; no rule
has another rate. One payment, by chain, transaction and log, pays once whichever rule,
site or account reports it; a repeat writes a 0-point entry. Its first report uses it,
even when the day's limit clips it to part or to nothing, and the database refuses a
second use (`point_cap_usage` check `payment_once`). A payment's points taken back in
full (`RegentPoints.reverse`) free the payment, so it can be reported again for the
right account under `RegentPoints.source_after_take_back/2`; the wrong account's day
stays used, and a partial take-back frees nothing. A payment that earned 0 for the
wrong account is freed by a correction of 0; only the award that used the payment
can be corrected by 0, once. The database holds one row per payment (a payment's
row is always account 0, program `lifetime`, window 1970-01-01, check `payment_row`, so
the allowance identity keeps it single), lets a correction row be 0 only when its own
category is `spending`, and allows one 0 correction per award. That the 0 correction is
of the award that used the payment is the library's rule, not the database's. A spending rule is reported only by its own site: `source_app` is the app in
the rule's id. Each kind of spending has its own rule, so each is switched on by itself:
`keyfleet.key_spend`, `patchbay.payment_spend`, `template.pinned_note_spend` and
`autolaunch.auction_bid_spend`. Autolaunch token buys earn no dollar points. Money that can still
come back, deposits, payments to yourself, sells and network fees are never reported.
`RegentPoints.summary/1` answers `dollars_today`: the dollars counted today and the
day's limit, in millionths of a dollar.

Awards save points only. The NFT bonus is added once per program period, at the
tally when the period ends (Sean, 9 October). Periods last 30 days, counted from
`starts_at`. Animata I, Animata II and Regents Club count together across the
account's verified linked wallets at the period-end snapshot: 1–2 pieces add 20%, 3–6 add
45%, 7 or more add 75%. One tier applies, without stacking, to the points the account
earned in that period after all limits and corrections, one-time awards included.
`RegentPoints.TallyAccount` writes one `period_bonuses` row per account and period with
the tier held at period end, and Oban retries a Base outage. The tier is never read
again for that period: an award checked after the tally, or a correction, moves the
period's earned total and bonus at the saved tier in the same locked transaction as
its ledger entry. An account's balance is its entries plus its period bonuses. Repeat actions earn at
most 100 base Points a UTC day, and spending at most 100 more, excluding one-time awards. The milestone catalog
totals 250 (`RegentPoints.Rules.milestone_total/0`); `template.first_agent_note` is
not approved at launch, so 240 can be earned then (Sean, 6 November). Sean approved the trial
values on 7 October; enabling any rule still needs his go. `RegentPoints.Rules.catalog/0` lists them,
`label/1` names each one for people, and `active/0` lists those earning now.
`tracked/0` lists the rules that are approved and have a source adapter on this site,
and a site's Points page shows only those, so it never offers an action that earns
nothing; `daily_apps/1`
names the apps of the daily rules it shows. There is no uncapped revenue-points rule.

Accepted events save the rule's points and daily limits with the rule. Delayed
processing uses that snapshot. A rule version never changes after approval; a changed
value is the rule's next version. `RegentPoints.Bonus` owns
the tiers used by the tally and the database constraint. `Bonus.current/1` reads
the tier an account's wallets hold now. The page shows a projected bonus and total,
with the actual period-end snapshot date. Moving an NFT changes this preview; only
holding it at the period-end snapshot determines the confirmed bonus.

Only the server system actor may intake, award or correct. Human actors with a
verified `human_account_id` can read only their own entries and summary. Rejections
and raw evidence are system-only. Corrections append negative entries, or a 0 entry
for a 0-point spending award, and never reopen a daily or count limit; the one thing
a correction frees is a spending award's payment, once it is taken back in full.
There is no browser award API.

## Migrate and verify

`RegentPoints.Migrator.up(MySite.Repo)` runs the package's generated migrations on
a dedicated connection, with its own history in `regent_points`. One designated
owner runs production migrations only with Sean's grant. The period bonus migration
removes the action-time NFT columns and the transfer cursor table; its rollback runs
only while the Points tables hold no awards.
The period-end snapshot migration records the existing verified wallet sets and
installs a capture trigger on the canonical account table, covering every site's
wallet changes. Wallet history, capture coverage and period snapshots are immutable.
Set `starts_at` at or after this capture coverage begins; older periods cannot be
reconstructed from current account state and are refused. Conflicting wallet ownership
at period end also refuses the tally. Snapshot creation is serialized, so concurrent
jobs reuse the same saved block. The generated capture migration wraps its statements
in one SQL block because Postgrex prepares one statement per call.
`RegentPoints.WalletSnapshot.owner/2` reads the same history for a site's
source action: the account holding a wallet at the moment of the event, or
`:unknown_owner` when no account, or more than one, held it then. It never
answers with the wallet's current owner.

Shared Ash SQL extensions belong to the host and are not migrated by this package.

For package development:

```sh
mix deps.get
mix check
mix ash.codegen --check
# After a resource change:
mix ash.codegen describe_change
```

The package's development Repo uses an isolated local database. Only package config
enables migration generation. Source adapters, approved rates/start time, the tally
cron on Regents and live product acceptance remain required before earning is enabled.

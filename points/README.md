# Regent Points

Share one account-linked Points ledger across Regent sites. The package owns the
`regent_points` schema, rules, award calculations, corrections and NFT reads.
Each host supplies verified source facts, its account lookups, Repo, PubSub and
Oban instance. Including the package starts no server, worker loop or migration.
Points and Credits have separate code and tables.

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
  unified_activity_starts_at: nil,
  approved_rules: [],
  adapters: %{}
```

Earning is off while `starts_at` is `nil`. Setting it starts the program and its
30-day periods, and it never changes or returns to `nil` afterwards: awards still
being checked, corrections and bonuses all count periods from it. To stop earning
later, empty `approved_rules`.

The accounts module implements `RegentPoints.Accounts`: `human/1` supplies the
verified wallet set for a canonical integer account ID; `agent_names/2` returns names
only for agents belonging to that account, as `{:ok, names}`. Return `{:error, reason}`
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
every other site leaves it out. All hosts use the same shared database and schema.
Use the same Repo for source actions and Oban. The package's notifier broadcasts
on the configured host PubSub under `points:<account_id>`; cross-node notification
delivery follows the host's PubSub topology.

## Record committed actions

In the source action's transaction, call the system-only domain action:

```elixir
{:ok, _} =
  RegentPoints.record_event(%{
    rule_id: "credits.purchase_settled",
    source_app: "regents",
    source_kind: "credits_purchase",
    source_event_key: purchase.id
  }, actor: %{role: :system})
```

Only those four reference fields enter the Oban job. No adapter, Points table or
chain read runs in the product transaction. The job is inserted in the source's own
transaction, so the action and its Points job commit or roll back together; an insert
failure raises and rolls back the action. Outside a transaction, the same API can
resubmit a reference to an already committed source. Never repeat a purchase, post
or wallet action to recover Points; reconcile from authoritative source records.

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
Credits evidence contains settled non-promotional `"purchased_usdc_atomic"`.
Any site that lists `RegentCredits` may credit any purchase, and its `on_credited`
module records `credits.purchase_settled` with `source_app: "regents"`, so the award
key is the same wherever it credits. Approve that rule and its start time on every
Credits host in one change; a host with it off would let a purchase it credits earn nothing.
Agent evidence contains `"attribution_link_id"`; Keyfleet additionally needs
`"key_id"` and `"ownership_epoch"`; social/registration milestones need a stable
restricted `"subject_key"`. Reports through WebMCP, HTTP, CLI, MCP or the site UI
must use the same business source identity for the same completed action. Transport
never establishes agent identity or creates a second award.

Patchbay solution and resolution awards, including their first-use milestones,
require integer `"asker_account_id"` and `"solver_account_id"` in verified evidence.
The adapter must resolve both to canonical human accounts across wallets and agents.
Intake rejects matching accounts and a beneficiary other than the solver (solution)
or asker (resolution). Different canonical accounts do not prove independent control.
Before enabling these rules, the source adapter must reject duplicate/spam content,
preserve the original solution identity across selection changes, and provide review
of reciprocal selection patterns. Use linked negative corrections to invalidate an
award later; corrections do not reopen spent limits. These product adapters and
pattern review are not shipped by this foundation.

Existing verified profile, social, ENS, pairing and registration state may qualify
once, using its actual verification time after program start, without reconnecting.
This is not historical activity backfill. The source adapter must prove current
eligibility and preserve the same account and subject milestone identities.

## Rates and allowances

The approved Credits basis is 10 points per USDC spent on purchased Credits, capped
at 100 base points per UTC day, separate from activity. Rule version 2 gives each
account and all its paired agents one combined 100-base-Point activity allowance
per UTC day and shared per-action counts, across every interface. One-time actions
use no daily allowance and remain once per canonical account.

Set `unified_activity_starts_at` to the same recorded UTC midnight on every host,
after deploying compatible services. Leave `starts_at`, approved rules and adapters
unchanged. A nil cutover preserves historical version 1 behavior until activation.
Version 1 has separate human (50) and agent (100) activity pools; its snapshots and
pre-cutover source events retain those rules. Version 2 never recalculates old awards.
Delayed intake selects the version by `source_action_at`, not processing time.

The revised recurring catalog is: Patchbay report 10 once/day, reply 5 twice/day,
accepted solution 20 once/day, and asker resolution 5 once/day. There is no
active-day or recurring vote rule. Keyfleet retains its 10-point first-vote milestone.
Two approved candidates stay out of the catalog until their products exist (Sean, 8
October): Keyfleet rollcall, 5 once/day, and independently verified Patchbay repair, 15
twice/day. All rules remain operationally disabled in the template.

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
its ledger entry. An account's balance is its entries plus its period bonuses. Version 2 daily
activity and Credits rewards together are at most 200 base Points, excluding milestones. The proposed milestone catalog
totals 510 (Sean, 9 October: the 10-point first agent note). Sean approved the trial
values on 7 October; enabling any rule still needs his go. `RegentPoints.Rules.catalog/0` lists them,
`label/1` names each one for people, and `active/0` lists those earning now.
`tracked/0` lists the rules this site has a source adapter for, and a site's Points
page shows only those, so it never offers an action nothing records; `daily_apps/1`
names the apps of the daily rules it shows. There is no uncapped revenue-points rule.

Accepted events save the Credits rate and daily limits with the rule. Delayed
processing uses that snapshot. Rule versions must remain immutable after approval;
future rate revisions need prospective versioned rules. `RegentPoints.Bonus` owns
the tiers used by the tally and the database constraint. `Bonus.current/1` reads
the tier an account's wallets hold now. The page shows a projected bonus and total,
with the actual period-end snapshot date. Moving an NFT changes this preview; only
holding it at the period-end snapshot determines the confirmed bonus.

Only the server system actor may intake, award or correct. Human actors with a
verified `human_account_id` can read only their own entries and summary. Rejections
and raw evidence are system-only. Corrections append negative entries and never
reopen allowances. There is no browser award API.

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

Refunding a Credits purchase does not remove the Points it earned, including when
verification happens after the refund (Sean, 9 October 2026).

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

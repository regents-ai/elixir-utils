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
  approved_rules: [],
  adapters: %{},
  nft_tracking_enabled: false
```

The accounts module implements `RegentPoints.Accounts`: `human/1` supplies the
verified wallet set for a canonical integer account ID; `wallet_holders/1` returns
canonical account IDs matching transfer parties; `agent_names/2` returns names
only for agents belonging to that account, as `{:ok, names}`. Return `{:error, reason}`
on lookup failure so the account page shows an error rather than a false missing-agent label. Agent `actor_id` is the verified paired
agent record ID. The shared `regent_names.platform_human_users` table must exist;
this package references it but never creates, updates or merges people.

The chain client implements `RegentPoints.ChainClient`: `rpc(%{chain_id: 8453}, method, params)`. Historical
`eth_call` must support canonical block hashes and archived balances. The transfer
watcher requires explicit `removed: false` on logs, and stops on a changed saved
block hash. Configure and verify the chosen RPC before enabling it. Every award with
linked wallets reads holdings at action time, whether or not NFT tracking is on. When
Base cannot answer, the award retries for about six hours (12 attempts); the last
attempt finishes it as not counted with reason `chain_unavailable`.

Add `points: 5` and `points_chain: 2` queues to the site's existing Oban instance.
Only Regents, the designated watcher owner, adds the minute cron for
`RegentPoints.WatchTransfers`; every other site leaves it out. All hosts use the same shared database and schema.
Use the same Repo for source actions and Oban. The package's notifier broadcasts
on the configured host PubSub under `points:<account_id>`; cross-node notification
delivery follows the host's PubSub topology.

## Record committed actions

In the source action's transaction, call the system-only domain action:

```elixir
RegentPoints.record_event(%{
  rule_id: "credits.purchase_settled",
  source_app: "regents",
  source_kind: "credits_purchase",
  source_event_key: purchase.id
}, actor: %{role: :system})
# Preserve the original source action result; Points is an optional side effect.
```

Only those four reference fields enter the Oban job. No adapter, Points table or
chain read runs in the product transaction. The single job insert uses a PostgreSQL
statement savepoint when inside a transaction. A failure returns `:not_queued`,
emits `[:regent_points, :enqueue, :failure]`, and leaves the product action usable.
A rollback of the product action removes its job. Outside a transaction, the same
API can resubmit a reference to an already committed source. Never repeat a purchase,
post or wallet action to recover Points; reconcile from authoritative source records.
Do not propagate a Points return value as the source action's result.

The background verifier calls the rule's configured adapter `verify(reference)`.
It must load authoritative persisted records, not trust browser assertions. Return
`{:ok, facts}`, `{:error, reason_atom}` for a permanent rejection, or
`{:retry, reason}` for an outage. Exceptions also retry through Oban. Invalid facts
and conflicting evidence get a permanent private `source_rejections` audit, without
changing an accepted event. Infrastructure failures retry; discarded Oban jobs need
operator diagnosis. An enqueue failure leaves no job and needs source reconciliation.

Facts have atom keys: `source_app`, `source_kind`, `source_event_key`, `account_id`,
`actor_kind` (`"human"` or `"agent"`), `actor_id`, `source_action_at`, `qualified_at`,
`evidence_ref`, `evidence` and `wallets`. Both times are UTC DateTimes. Freeze the
beneficiary and linked wallets at action time. Source identity must match the job.
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
at 100 base points per UTC day. Privy-account daily actions share 50 per day, and
connected agents share 100. Those actions come from the apps the daily rules name:
today only Patchbay. Per-action counts are separate for humans and the pooled agents.
More agents, keys or wallets do not create extra allowances, and one completed event
belongs to only one pool. One-time actions use no daily allowance and are once per
canonical account across sites, wallets, keys and agents.

The revised recurring catalog is: Patchbay report 10 once/day, reply 5 twice/day,
accepted solution 20 once/day, and asker resolution 5 once/day. There is no
active-day or recurring vote rule. Keyfleet retains its 10-point first-vote milestone.
Two approved candidates stay out of the catalog until their products exist (Sean, 8
October): Keyfleet rollcall, 5 once/day, and independently verified Patchbay repair, 15
twice/day. All rules remain operationally disabled in the template.

Animata I, Animata II and Regents Club count together across verified linked
wallets. The highest tier adds 20% for 1–4 pieces, 45% for 5–9, or 75% for 10+.
The highest tier applies once, without stacking, only to base points actually
awarded after all limits, and also to one-time awards: the daily maximum
is 250 base or 437.5 at the highest tier. The proposed milestone catalog totals 500
base or 875 at the highest tier. Sean approved these trial values on 7 October;
enabling any rule still needs his go. `RegentPoints.Rules.catalog/0` lists them,
`label/1` names each one for people, and `active/0` lists those earning now.
`tracked/0` lists the rules this site has a source adapter for, and a site's Points
page shows only those, so it never offers an action nothing records; `daily_apps/1`
names the apps of the daily rules it shows. There is no uncapped revenue-points rule.

Accepted events save the Credits rate and daily limits with the rule. Delayed
processing uses that snapshot. Rule versions must remain immutable after approval;
future rate revisions need prospective versioned rules. NFT awards use canonical
holdings and verified linked wallets at action time, not processing time. Transfers
refresh both parties and affect subsequent actions without repricing earlier awards.
The page displays requested base, awarded base, bonus and total for capped awards.
`RegentPoints.Bonus` owns the tier definition used by
awards, the account calculation, the database constraint and the page.

Only the server system actor may intake, award or correct. Human actors with a
verified `human_account_id` can read only their own entries and summary. Rejections
and raw evidence are system-only. Corrections append negative entries and never
reopen allowances. There is no browser award API.

## Migrate and verify

`RegentPoints.Migrator.up(MySite.Repo)` runs the package's generated migrations on
a dedicated connection, with its own history in `regent_points`. One designated
owner runs production migrations only with Sean's grant. The package ships one
initial migration for the final schema. It expects a fresh Points schema; an older
local prototype requires an explicitly authorized reset before using this version.
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
enables migration generation. Source adapters, approved rates/start time, watcher
ownership and live product acceptance remain required before earning is enabled.

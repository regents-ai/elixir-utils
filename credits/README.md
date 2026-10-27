# RegentCredits

One prepaid Credits balance per Privy account, shared by every Regent site.
One Credit is one US dollar. Credits come from purchases (USDC on Base or
Ethereum, or a card or Link through Stripe) and admin gifts, and are spent through holds a site places and
closes.

Every site keeps the ledger in the `regent_credits` schema of its own
database connection, so a site's change and its Credits commit or fail in
one transaction. In production all sites share one database, so they share
one ledger.

## Install

```elixir
{:regent_credits,
 git: "https://github.com/regents-ai/elixir-utils.git", ref: @elixir_utils_ref, sparse: "credits"}
```

```elixir
config :ex_money, custom_currencies: [{:XRC, name: "Credits", digits: 6}]

config :regent_credits,
  repo: MySite.Repo,
  pubsub: MySite.PubSub,
  notifications: MySite.Notifications,
  admins: ["did:privy:..."],
  chain_client: MySite.Chain.Client,
  chains: %{
    base: %{chain_id: 8453, name: "Base", rpc_url: "https://..."},
    ethereum: %{chain_id: 1, name: "Ethereum", rpc_url: "https://..."}
  }
```

- Start `RegentCredits.Listener` after PubSub and the site's own
  `Postgrex.Notifications` connection on the database's direct address, named
  in the `notifications:` setting, under a `:rest_for_one` supervisor; Agents'
  listener shares the same connection. A page showing a balance subscribes to
  `RegentCredits.topic(privy_user_id)` and hears `:credits_changed` whenever
  that balance changes on any site.
- `chain_client` implements `RegentCredits.ChainClient`: `transaction/2`,
  `receipt/2`, `block_number/1` and `logs/2` (`eth_getLogs` over at most 500
  blocks), all read at `latest`. A JSON-RPC error answer comes back as
  `{:error, {:rpc, error}}`; the deposit reader reads a span refused that way
  again in halves.
- Credits tells the site about purchases through `RegentCredits.Signals`:
  `:purchase_credited` and `:purchase_attributed`, each with `purchase_id`
  and `privy_user_id`. The site listens with `signals_in` on a resource of
  its own and adds the `:ash_signals` compiler (and, with the code reloader,
  `reloadable_compilers`). A listener with the default delivery runs inside
  the credit's transaction: work it queues commits with the credit, and a
  listener that fails rolls the credit back. Every site that lists the
  `RegentCredits` domain may credit any purchase, so each one's listener does
  the same work.
- The site's Oban needs a `:regent_credits` queue, and its AshOban
  configuration lists the `RegentCredits` domain. The library starts no Oban
  of its own.
- Migrations: `RegentCredits.Migrator.up(MySite.Repo)` creates the schema and
  runs the library's migrations. Locally each site runs it; in production
  only Regents does. The ledger's money type is installed database-wide in
  `public`, so a site's repo does not list `AshMoney.AshPostgresExtension`;
  a site that adopts `ash_money` later skips its own install of that type,
  which already exists.
- Database rules refuse any edit or delete of a transfer. Balances belong to
  `ash_double_entry` and are rewritten with each transfer; holds, purchases,
  gifts and refunds change only through the library's actions.

## Actors

Every call passes a `RegentCredits.Actor`:

| Actor | May |
| --- | --- |
| `Actor.person(privy_user_id, wallets, site)` | hold its own Credits, report purchases sent from `wallets` (the wallets the site's sign-in verified), read its own rows |
| `Actor.agent(privy_user_id, agent_address, site)` | hold its person's Credits within the person's agent settings |
| `Actor.site(site)` | close the holds that site placed; attach wallets at sign-in |
| `Actor.admin(privy_user_id)` | give Credits, start and close refunds, read everything (when `admins` names it) |

Agent settings are saved only by regents.sh (`Actor.person(id, wallets, "regents")`).

Enabling a spending grant is disabled by default. Keep it disabled during the shared
rollout: older Credits writers must not use newly enabled grants. Only after every
writer supports pairing-bound grants may the deployment configuration explicitly set
`config :regent_credits, agent_grants_enabled: true`. Pages can read
`RegentCredits.agent_grants_enabled?/0` to explain availability. Request parameters,
actor privileges and action context cannot enable this setting. The gate does not
prevent disabling a grant or settling an existing hold, and does not itself revoke
existing grants.

## Spending

```elixir
{:ok, hold} = RegentCredits.hold(bid_id, privy_user_id, Decimal.new("2.50"), "offer_bid", actor: person)

RegentCredits.give_back(bid_id, "outbid", actor: site)
RegentCredits.charge(fix_id, actor: site)
RegentCredits.carry_over(pre_bid_id, bid_id, "offer_bid", actor: site)
RegentCredits.settle(bid_id, returned, used, forfeited, actor: site)
RegentCredits.pay_bounty(post_id, answer_owner, actor: site)
RegentCredits.take_back(post_id, actor: site)
```

- Given Credits are spent first; what comes back returns as the kind it was.
- Carrying a hold is a server operation between two distinct reservation keys.
  Carrying it to its own key is refused before anything changes.
- A hold is closed once. The same call again answers with the first result;
  the same key with other details is refused.
- A site that locks its own rows (an Offer slot) calls the hold after them,
  inside its own transaction. See `RegentCredits.Ledger` for the order.
- A site that holds and closes for several people in one transaction first
  calls `RegentCredits.lock_holds(keys, privy_user_ids, actor: site)` with
  every hold it may close and every person it may hold for.

## Buying

The panel builds the steps with `RegentCredits.Chains.steps(chain, dollars,
number)` into a `RegentChain.Review`, reports each sent Buy with
`RegentCredits.report_purchase/7`, and calls `RegentCredits.check_purchase/2`
every two seconds while it waits, passing the owning person actor. Purchase details
are never returned to an anonymous caller or another person. A report is saved only once the chain holds
the transaction as this purchase's Buy from the reported wallet. Until then it
is refused with `:not_seen_yet`, and the panel reports it again every two
seconds for about five minutes. Each report reads the chain, so the site calls
it behind a per-person limit, for example 120 a minute. The site's Oban checks every purchase still
open once a minute. Base purchases count at the latest block; Ethereum
purchases once 12 blocks sit on top of theirs and it is still in that block.

The site's Oban also reads every Credits deposit on Base from the chain every
five minutes (`RegentCredits.Deposits`), up to ten minutes behind the newest
block, and credits each exactly as it landed, whether or not a page reported
it: to the account holding the paying wallet, else to the account that
reported it from that wallet, else under that wallet until an account signs
in with it or reports it. Each wallet's payment in a transaction is one
purchase: it and its report credit once between them, and two wallets paying
in one transaction are credited separately.

### By card or Link

A site with Stripe keys takes card and Link purchases through Stripe Checkout
with the Payment Element on its own page (`RegentCredits.CardPurchase`):

    config :regent_credits, :stripe,
      secret_key: "sk_live_...",
      webhook_secret: "whsec_..."

- `RegentCredits.card_payments?()` says whether the site has keys, and
  `RegentCredits.card_price(credits)` the card fee and total in cents: whole
  dollars of Credits, $5 to $500, plus 2.9% + 30 cents so the Credits arrive whole.
- `RegentCredits.start_card_purchase(privy_user_id, credits, return_url,
  %{email: email}, actor: person)` opens the Checkout Session and answers its
  `client_secret` for `stripe.initCheckoutElementsSdk`. With Stripe's test keys
  only Credits admins may start one, since a test card adds real Credits to the
  shared ledger. A person whose Credits are below zero cannot start one.
- The site's webhook passes Stripe's raw body and `Stripe-Signature` header to
  `RegentCredits.card_notice(payload, signature, actor: site)`. A paid session
  adds the Credits once; a refund takes back its share of them and a dispute the
  rest, even below zero (Sean, 27 October 2026). The webhook listens for
  `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
  `charge.refunded` and `charge.dispute.created`, and answers an error so Stripe
  sends the notice again.
- After the payment confirms, the page calls
  `RegentCredits.settle_card_purchase(session_id, actor: person)`, which reads the
  session from Stripe and adds the Credits if the webhook has not yet.

Every Regent site uses the same Stripe account, so each webhook hears every
site's card payments, and any of them credits one once.

## Gifts and refunds

- `RegentCredits.give(key, recipients, amount, actor: admin)`: Privy account
  ids or wallet addresses; one gift per key and recipient. A gift to a wallet
  an account holds goes straight to that account.
- `RegentCredits.attach_wallets(privy_user_id, wallets, actor: site)`: at
  sign-in or when a wallet is linked, records that the account holds exactly
  those wallets and moves Credits waiting under them to the account.
- `RegentCredits.start_refund(purchase_id, actor: admin)` takes the Credits
  out while that many purchased Credits are still in the account, neither set
  aside nor spent. Credits are non-refundable; the team decides each exception
  (Sean, 13 October 2026);
  `RegentCredits.close_refund(refund_id, tx_hash, actor: admin)` checks the
  Treasury Safe's USDC transfer back to the paying wallet.

## Account history

`RegentCredits.history(actor: person)` returns everything that moved the person's
balance, newest first, one entry for each thing that happened: a purchase, a gift,
a refund, Credits set aside on a site, and held Credits returned, spent or received.
The ledger writes one transfer for each kind of Credit an operation moves; an entry
adds a hold's transfers together, so a hold that took given and purchased Credits is
one entry, and its close is one entry for what came back and one for what was used.

Each entry has `id`, `kind`, `at`, `amount` (always positive), `direction` (`:in` or
`:out` of what the person can spend, `:none` for held Credits that were used), and
the facts that apply, `nil` otherwise: `site`, `purpose`, `reason`, `agent_address`
and `pairing_id` (the person's agent that set the Credits aside), `key`, `tool` and
`request` (what led to the spend, below), `note`, `chain`, `tx_hash`, `refund_status`
and `refund_sent_at`. `RegentCredits.History` lists the
kinds. Credits a person received from someone else's hold name the site only, never
who paid. `RegentCredits.History.Words` holds the words every site shows for an
entry (`line/1`) and for a site, purpose, reason, chain and failed purchase; a page
never reads an operation string, and a code with no words there is shown as nothing.

`RegentCredits.history_of(privy_user_id, actor: admin)` answers the same entries for
the person a Credits admin names, and nobody else may call it. The team's page shows
them with the same words, so the team reads exactly what the person reads.

### What led to a spend

When a site places a hold it may say what led to it, so the person and the team can
see it beside the spend (Sean, 13 October 2026):

```elixir
RegentCredits.hold(key, privy_user_id, amount, "offer_bid",
  %{tool: "offers.bid", request: arguments_as_sent}, actor: actor)
```

- `tool` is the tool or page name as the site's capability list names it, at most
  120 characters. A person's own press sends `tool` alone. It is the site's own
  constant, never text from a request: a `tool` that is too long refuses the hold.
- `request` is the tool's arguments as the agent sent them, at most 4,000 bytes.
  Send it only for a tool whose accepted arguments always fit and hold nothing a
  visitor typed about themselves: a bid, yes; a post or a fix request, no. For those
  the entry's `key` is the site's own id of the post or request, where the words
  already are. A `request` over 4,000 bytes, or one holding a zero byte or bytes that
  are not UTF-8, is not kept and the hold is placed without it: a record-keeping limit never refuses a spend.
  The database holds the same limit.
- Never send sign-in headers, proofs, signatures or tokens. An agent may put a key
  in its arguments, so pass only the arguments the site means to keep.
- A carried-over hold keeps the first hold's `tool` and `request`.
- The person and Credits admins read both. A paired agent reads the whole account's
  history, its sibling agents' spends included, with `tool`, `key` and which agent
  spent; it is given `request` only on a hold it placed itself, in the history and on
  a hold alike, so one agent's words never reach another as data.
- A page shows `request` as plain text, marked as written by the agent, never as a
  link or markup, and never hands it to a model or a checker.
- Never put `request` in a log line, error report, telemetry or a job's arguments.
  Each hold that sends one emits `[:regent_credits, :hold, :request]` with its size in
  `bytes`, the `site`, and whether it was `kept?`.
- Nothing removes a stored `request` later; it stays with its hold.

Ownership comes from the actor, never a supplied account ID. Nothing is removed to
limit history length. A page holds the entries of at most 50 transfers and never ends
inside one entry; pass `%{after: page.next}` to read older entries while `page.more?`
is true. Entries are ordered by when each site wrote them, by that site's own clock.
If two sites write for one person within the same few milliseconds and their clocks
differ, one hold's close can fall either side of a page edge and read as two lines
whose amounts still add up to it. That is expected, not a fault. Purchases that added no Credits (still being checked, or failed with a
reason) are not in the history; `RegentCredits.purchases(actor: person)` reads them.
All amounts retain six decimal places of precision.

Refunding a purchase does not remove the Points it earned (Sean, 9 October 2026).

## Development

Tests use a local PostgreSQL 17 database named `regent_credits_test_ledger`.

```sh
mix deps.get
mix check
```

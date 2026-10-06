# RegentCredits

One prepaid Credits balance per Privy account, shared by every Regent site.
One Credit is one US dollar. Credits come from purchases (USDC on Base or
Ethereum) and admin gifts, and are spent through holds a site places and
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
  admins: ["did:privy:..."],
  chain_client: MySite.Chain.Client,
  chains: %{
    base: %{chain_id: 8453, name: "Base", rpc_url: "https://..."},
    ethereum: %{chain_id: 1, name: "Ethereum", rpc_url: "https://..."}
  }
```

- Start `RegentCredits.Listener` after the repository and PubSub. A page
  showing a balance subscribes to `RegentCredits.topic(privy_user_id)` and
  hears `:credits_changed` whenever that balance changes on any site.
- `chain_client` implements `RegentCredits.ChainClient`: `transaction/2`,
  `receipt/2` and `block_number/1`, all read at `latest`.
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
- A hold is closed once. The same call again answers with the first result;
  the same key with other details is refused.
- A site that locks its own rows (an Offer slot) calls the hold after them,
  inside its own transaction. See `RegentCredits.Ledger` for the order.

## Buying

The panel builds the steps with `RegentCredits.Chains.steps(chain, dollars,
number)` into a `RegentChain.Review`, reports each sent Buy with
`RegentCredits.report_purchase/7`, and calls `RegentCredits.check_purchase/2`
every two seconds while it waits. The site's Oban checks every purchase still
open once a minute. Base purchases count at the latest block; Ethereum
purchases once 12 blocks sit on top of theirs and it is still in that block.

## Gifts and refunds

- `RegentCredits.give(key, recipients, amount, actor: admin)`: Privy account
  ids or wallet addresses; one gift per key and recipient. A gift to a wallet
  an account holds goes straight to that account.
- `RegentCredits.attach_wallets(privy_user_id, wallets, actor: site)`: at
  sign-in or when a wallet is linked, records that the account holds exactly
  those wallets and moves Credits waiting under them to the account.
- `RegentCredits.start_refund(purchase_id, actor: admin)` takes the Credits
  out while the account has never used Credits;
  `RegentCredits.close_refund(refund_id, tx_hash, actor: admin)` checks the
  Treasury Safe's USDC transfer back to the paying wallet.

## Development

Tests use a local PostgreSQL 17 database named `regent_credits_test_ledger`.

```sh
mix deps.get
mix check
```

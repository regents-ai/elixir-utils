# Regent Names

The Regent names a person's wallets hold, and the free claims those wallets
may still make, shared by every Regent site.

A Regent name is recorded twice: under the parent it was granted from (for
example `sol.agent.base.eth`) and under `regent.eth` (`sol.regent.eth`). The
records live in the `regent_names` schema of the shared database. They were
imported once; this library never migrates them, and a free claim is a record
there and nothing else. No transaction is sent.

## Setup

```elixir
config :regent_names, repo: MySite.Repo, privy_app_id: "the site's Privy app id"
```

Add `RegentNames` to the site's `ash_domains`.

## Reads and the one write

- `RegentNames.list_my_claims(actor: actor, page: [limit: 50])`: the names the
  actor's wallets hold, oldest first, 50 at a time (keyset pages).
- `RegentNames.claims_available(actor: actor)`: `{:ok, %{free: n, paid: n}}`,
  the free claims granted at the snapshot and not yet used, and the paid claims
  bought and not yet spent.
- `RegentNames.label_problems(label)`: why a label can't be a name, as
  sentences for the person typing it (3 to 14 lowercase letters, numbers and
  hyphens, never starting or ending with a hyphen).
- `RegentNames.label_claimed?(label, actor: actor)`: whether any claim holds it.
- `RegentNames.claim_free_name(label, actor: actor)`: records the name for the
  wallet whose free claim pays for it (the sign-in's main wallet first, then
  its linked wallets in order) and spends that free claim, together or not at
  all. Two claims racing for a wallet's last free claim cannot both succeed.
- `RegentNames.present(claim)`: the claim as an API answer, without payment or
  entitlement fields.

## Who may do what

Reads take a person signed in on the site (`%{role: :human,
human_account_id: integer, wallet_addresses: [...]}`), an agent the person
paired (`RegentAgents.Checks.Paired`) or a fresh Privy sign-in for the site's
own app. Only a person claims. Every row is matched to the actor's own
verified `wallet_addresses`, lowercased; a row for any other wallet is never
read.

## Checks

`mix check` in this folder, with PostgreSQL on 127.0.0.1:5432 and the test
database created first: `MIX_ENV=test mix ecto.create -r RegentNames.TestRepo`.

# Regent Agents

One pairing between a person and their agent, shared by every Regent site.

A person makes a pairing code on their regents.sh Account page and gives it to
their agent. The agent pairs on any Regent site, signing the request with its
SIWA key, and afterwards every site's check-in answers with that same pairing.
The agent's side is described in the sign-in guide at
https://siwa.regents.sh/skill.md.

- `POST /api/agents/v1/pair` with `{code, name, harness}` answers `201 {data: agent}`.
- `GET /api/agents/v1/me` answers `200 {data: agent + account}`.
- Both answers carry `registry_listing`: the agent's page in the agent registry,
  as the SIWA service names it, or null when the agent has no listing;
  `human_backed`: whether a person verified with World ID stands behind it; and
  `same_person_agent_count`: how many agents, this one included, that same
  person stands behind, or null when none does. The first person the SIWA
  service's `agentBook` names stays on the paired agent for good; a later `null`,
  or another person, changes nothing, and each request naming the same person
  saves their agent count (`RegentAgents.HumanBacking`). Both fields come from
  what was saved. Every Regent site
  uses these two names. The person's World ID number is saved only to group
  their agents; it is never shown, logged or answered.
- A refusal is `{error: {code, message, hint}}`: `pairing_failed` (400),
  `harness_unknown` (400, also for a harness the site does not offer; the hint lists `Harness.offered/0`), `not_paired` (404),
  `person_not_here` (403, a check-in before the person's first sign-in on this site),
  `verification_failed` (401), `duplicate_proof`, `unsupported_query` or
  `missing_signed_body` (401, the shared plug's own refusals: a repeated
  signature header, a query string, a body it did not capture whole),
  `siwa_request_failed` (503), or the SIWA
  service's own refusal, passed on unchanged: its status, code, message and a
  hint written for the site and the agent's signing tool.
- A site that runs `Siwa.AgentAuthPlug` for its own agent requests answers a
  refused signature the same way: its `deny/2` hook calls
  `RegentAgents.Refusal.describe(refusal, hint)` for every refusal it did not
  make itself, with its own line on how an agent signs in to that site, and
  sends the status and `{error: {code, message, hint}}` it returns. On purpose,
  a refusal from the SIWA service below 500 that comes without its own code,
  message and hint is answered `verification_failed` (401): its status, a 429
  say, is not passed on.

The person is named by their Privy user ID and the agent by its key's address.
One key belongs to one person. A code works once, for ten minutes. A new code
leaves the person's earlier ones working until they expire, and a person may
make as many as they like. One account holds at most 100 paired agents; past
that, pairing answers `agent_limit` and the code stays unused. Pairing only
says whose agent this is: what a paired agent may do on a site stays that
site's decision.

## Adopting it on a site

Depend on it the way the site depends on `regent_identity`:

```elixir
{:regent_agents, git: @regents, ref: @regents_ref, sparse: "agents"}
```

Configure it with the site's repository, PubSub, SIWA audience, and how a
check-in names the person's account (a function taking the Privy user ID and
returning a JSON-ready map, or nil until the person first signs in on the site,
which answers the check-in with `person_not_here`):

```elixir
config :regent_agents,
  repo: MySite.Repo,
  pubsub: MySite.PubSub,
  account: {MySite.Agents, :account},
  siwa: [url: "https://siwa.regents.sh", audience: "mysite"]
```

A pairing box lists `RegentAgents.Harness.offered/0`. ChatGPT pairs through a
connected plugin and the `register_identity`, `get_identity` and `pair_identity`
tools, so it is listed, and the pair request accepts it, only on a site that
serves them and sets `chatgpt_pairing: true` here.

Mount the two requests behind the site's own rate limit (Regents allows 10
pair requests and 60 check-ins a minute from one address). Mount them outside
any agent sign-in pipeline: the package checks the signature itself, and a
second check would spend the signed request, so the agent would be told
`request_replayed`. The endpoint's body reader must keep the raw body in
`conn.assigns.raw_body`, because the agent signs the exact bytes:

```elixir
forward "/api/agents/v1", RegentAgents.HTTP
```

Start the listener in the application's children, after the repository and
PubSub:

```elixir
RegentAgents.Listener
```

It opens one connection of its own with the repository's settings and listens
for the changes every site announces through the shared database. That needs
a direct connection: a pooler that hands out connections per transaction
drops the listening.

A page acting for a signed-in person passes
`%RegentAgents.Person{privy_user_id: ...}`, built only from the site's own
verified session, to `issue_pairing_code`, `list_my_agents`, `get_my_agent`
and `unpair_agent`, and subscribes to
`RegentAgents.topic(privy_user_id)` to hear `:agents_changed` whenever that
person's agents are paired, check in or are unpaired on any
Regent site.

The side panel offers the ten agents in `RegentAgents.Harness.featured/0`:
any agent, Codex, Grok Bot, Muse, Hermes, Dots, NemoClaw, OpenClaw, Claude Code
and Pi. The message a person pastes to their agent is
`RegentAgents.PairingMessage.text(code, site_name, origin, harness)`, the same
words on every site, with one more line for Codex, Grok Bot, Hermes and Muse, for
the mistake each most often makes on its first pairing.

`RegentAgents.Activity.recent(agent, operations)` reads what a paired agent has
done across the Regent sites, newest first, 20 at a time; pass the page's `next`
as a third argument to read the page after it. `operations` names the site's own
requests, built from its capability list: `[%{method: "POST", path:
"/tools/notes/{id}/pin", words: "Pinned a note"}, ...]`. Any other request is worded from its method alone. It needs the
site's own reader key from the SIWA service:

```elixir
config :regent_agents, activity_read_token: System.get_env("SIWA_ACTIVITY_READ_TOKEN")
```

## Migrations

Regents alone runs `RegentAgents.Migrator.up(Regents.Repo)` in its release step.
It creates the `regent_agents` schema with its own migration ledger. Other sites
never run it.

## Checks

`mix check` in this folder, against the local database `regent_agents_test_local`
(with `MIX_TEST_PARTITION=_<suffix>`, `regent_agents_test_local_<suffix>`).

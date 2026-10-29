# Regent Agents

One pairing between a person and their agent, shared by every Regent site.

A person signs in on a Regent site and makes a pairing code with Pair New Agent
on its Account page, then gives the code to their agent. The agent pairs on any Regent site, signing the request with its
SIWA key, and afterwards every site's check-in answers with that same pairing.
The agent's side is described in the sign-in guide at
https://siwa.regents.sh/skill.md.

- `GET /api/agents/v1/whoami` answers `200 {data: {agent, audience,
  authenticated, pairing, status, allowed, next_step}}` for every signed agent,
  without checking in. `status` is `not_paired` (paired to nobody),
  `person_not_here` (paired, but its person has never signed in on this site) or
  `paired` (it acts for its person); `allowed` is the site's list of short
  sentences for that status; `next_step` is one sentence, null when `paired`.
  `pairing` is `{id, paired_at}` or null. `RegentAgents.HTTP.next_step/1` gives
  the same next step for a site's own agent guides.
- `POST /api/agents/v1/pair` with `{code, name, harness}` answers `201 {data: agent}`.
- `GET /api/agents/v1/me` answers `200 {data: agent + account}`.
- `whoami`'s `agent` and both answers carry `registry_listing`: the agent's page
  in the agent registry, as the SIWA service names it, or null when the agent has
  no listing;
  `human_backed`: whether a person verified with World ID stands behind it; and
  `same_person_agent_count`: how many agents, this one included, that same
  person stands behind, or null when none does. The first person the SIWA
  service's `agentBook` names stays on the paired agent for good; a later `null`,
  or another person, changes nothing, and each request naming the same person
  saves their agent count (`RegentAgents.HumanBacking`). Both fields come from
  what was saved; `whoami` answers them as the SIWA service names them on that
  request, before any pairing has saved them. Every Regent site
  uses these two names. The person's World ID number is saved only to group
  their agents; it is never shown, logged or answered.
- A refusal is `{error: {code, message, hint}}`: `pairing_failed` (400),
  `harness_unknown` (400, also for a harness the site does not offer; the hint lists `Harness.offered/0`),
  `agent_not_paired` (403, a check-in from an agent paired to nobody),
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
that, pairing answers `agent_limit` and the code stays unused. An agent's name
follows the one rule for names on every Regent site (`RegentFormat.Name`): 1 to
80 characters with no hidden characters. Pairing with any other answers
`invalid_name` and the code stays unused. Pairing only
says whose agent this is: what a paired agent may do on a site stays that
site's decision.

## Adopting it on a site

Depend on it the way the site depends on `regent_identity`:

```elixir
{:regent_agents, git: @regents, ref: @regents_ref, sparse: "agents"}
```

Configure it with the site's repository, PubSub, SIWA audience, how a
check-in names the person's account (a function taking the Privy user ID and
returning a JSON-ready map, or nil until the person first signs in on the site,
which answers the check-in with `person_not_here`), and what an agent may do on
the site in each status, as `whoami` tells it. There is no default list: every
site writes its own, true to its routes and policies. The `siwa` settings read
the verify key from the environment, so they go in `config/runtime.exs`.

```elixir
config :regent_agents,
  repo: MySite.Repo,
  pubsub: MySite.PubSub,
  account: {MySite.Agents, :account},
  allowed: %{
    "not_paired" => ["Read public pages and public tools.", "Pair with a code from your person."],
    "person_not_here" => ["Read public pages and public tools."],
    "paired" => ["Read public pages and public tools.", "Read and write your person's notes."]
  },
  siwa: [
    url: "https://siwa.regents.sh",
    audience: "mysite",
    verify_key: System.fetch_env!("SIWA_SITE_VERIFY_KEY")
  ]
```

`verify_key` is the site's own key in the SIWA service's
`SIWA_SITE_VERIFY_KEYS`. It is sent with every signed request the site asks the
service to check, and it names the one audience the service checks it for.
`audience` and `verify_key` name the same site. If the service refuses the key,
or answers for another audience, the site logs an error and agents are told the
sign-in service could not be reached (503) until the settings are fixed.

A pairing box lists `RegentAgents.Harness.offered/0`. ChatGPT and Claude, the
hosted runtimes, pair through the site's hosted connection (`regent_mcp_agents`)
and its `register_identity`, `get_identity`, `pair_identity` and `check_in`
tools. A site lists the ones whose connection it serves, and only those are
offered and accepted by the pair request:

```elixir
config :regent_agents, hosted_pairing: [:claude]
```

Switching on Claude this way does not offer ChatGPT. A site that lists none
offers every agent but the two.

Mount the requests behind the site's own rate limit (Regents allows 10
pair requests and 60 check-ins a minute from one address). Mount them outside
any agent sign-in pipeline: the package checks the signature itself, and a
second check would spend the signed request, so the agent would be told
`request_replayed`. The endpoint's body reader must keep the raw body in
`conn.assigns.raw_body`, because the agent signs the exact bytes:

```elixir
forward "/api/agents/v1", RegentAgents.HTTP
```

The listener hears the changes every site announces through the shared
database. Listening needs a connection of its own on the database's direct
address: a pooler that hands out connections per transaction drops it. The
site opens one `Postgrex.Notifications` connection, names it in the
`:notifications` setting, and starts the listener after it and PubSub under a
`:rest_for_one` supervisor, so a new connection brings a new listener. Credits'
listener shares the same connection:

```elixir
config :regent_agents, notifications: MySite.Notifications

children = [
  {Postgrex.Notifications, [name: MySite.Notifications] ++ direct_options},
  RegentAgents.Listener
]

Supervisor.init(children, strategy: :rest_for_one)
```

A page acting for a signed-in person passes
`%RegentAgents.Person{privy_user_id: ...}`, built only from the site's own
verified session, to `issue_pairing_code`, `list_my_agents`, `get_my_agent`,
`rename_agent` and `unpair_agent`, and subscribes to
`RegentAgents.topic(privy_user_id)` to hear `:agents_changed` whenever that
person's agents are paired, renamed, check in or are unpaired on any
Regent site. On that notice, `agents_paired_with(codes)` names the agent each of
the codes on screen paired, so a box holding several codes names each agent
under its own code. An agent picks its own name when it pairs; the person may rename it,
and the new name shows on every Regent site.

The pairing box offers the ten agents in `RegentAgents.Harness.featured/0`:
any agent, Codex, Grok Bot, Muse, Hermes, Dots, IronClaw, OpenClaw, Claude Code
and Pi. The message a person pastes to their agent is
`RegentAgents.PairingMessage.text(code, origin, harness, opts)`, the same words on
every site. It opens "Pair with my Regents Labs account on <site's host>", so the
agent learns the account is the person's one Regents Labs account and which site
it pairs on. ChatGPT and Claude are told to connect through the site's plugin or
connector and to pair with `pair_identity`, naming their harness. Every other
agent is told to keep its own key: "begin every
shell with export SIWA_AGENT_HOME=~/.siwa-agent/<runtime>", the folder named
after its runtime (`claude-code`, `codex`, `grok-bot` and so on, and
`YOUR-RUNTIME` for any agent or none named), so agents sharing one computer pair
as separate agents. Codex, Grok Bot, Hermes and Muse get one more line, for the
mistake each most often makes on its first pairing. `setup:` adds the site's own
lines for that agent after those. `start:`, a path on the same site taken from a
pairing link, ends the message "Once paired, start at <page>"; without it the
line is left out.

`RegentAgents.Activity.recent(agent)` reads where a paired agent has been
active across the Regent sites since it paired: a line per site and day for the
last 30 days, newest day first, with its first and last request that day, and
its registry listing. `RegentAgents.Activity.latest/1` picks the newest of them.
The SIWA service answers a site's reads up to 600 a minute, so a site keeps each
agent's reading for a few minutes and shares it with every page. It needs the
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

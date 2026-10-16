# Changelog

## 0.1.0 (unreleased)

- `RegentAgents.Harness.featured/0` lists the ten agents the side panel offers:
  any agent, Codex, Grok Bot, Muse, Hermes, Dots, NemoClaw, OpenClaw, Claude Code
  and Pi.
- Every pairing message says the code works once, for ten minutes, and to ask for
  a new one if it fails. Codex's adds what to do when its sandbox blocks the
  network and where pair.json goes; Grok Bot's says never to post the code in
  public; Hermes's says to keep one key; Muse's keeps the SIWA service's other
  address.
- A check-in before the person's first sign-in on the site answers
  `person_not_here` (403), the code every Regent site gives an agent whose person
  has not signed in there yet, asking the agent to have its person sign in
  there once, instead of crashing: the site's `account` callback returns nil
  until that sign-in. Every site's callback returns a map or nil.
- The check-in looks up the account before it records contact, so a
  `person_not_here` answer leaves the agent's last contact unchanged and
  announces nothing.
- `check_in_agent/2` takes the person's Privy user ID and records contact only
  when the agent's pairing is still with that person; otherwise it answers
  `not_paired`. The check-in request passes the person whose account it looked
  up, so an agent unpaired and paired to someone else in between never answers
  with the previous person's account.
- The pair request accepts only the harnesses the site offers
  (`RegentAgents.Harness.offered/0`), and its `harness_unknown` hint lists
  those, so a site without `chatgpt_pairing: true` refuses `chatgpt`.
- New `RegentAgents.Refusal.describe/2`: the status, code, message and hint an
  agent gets when its signed request is refused, for a site's own
  `Siwa.AgentAuthPlug` `deny/2` hook to call with its sign-in hint. The pairing
  and check-in requests use it too. When the sign-in service cannot be reached
  the hint now reads "Try again in a moment."
- `RegentAgents.Activity.recent/3` takes the site's own operations and words
  each request to the site's audience the way the site names it ("Pinned a
  note"). A request
  no site names is worded from its method: a POST is "Sent a request", never a
  change, since it may only read.
- `RegentAgents.Activity` (what a paired agent has done across the Regent sites,
  read with the site's `activity_read_token`) and `RegentAgents.PairingMessage`
  (the message a person pastes to their agent), moved here from ash-template.
- Moved here from the Regents repository (Regents main b258ae02) into
  elixir-utils `ash_components/agents`, owned by the ash-template lane. Module
  names, routes, settings, mix tasks and migrations are unchanged.
- elixir-utils siblings are path dependencies, and the package runs the
  elixir-utils `mix check`.
- Runs on Ash 3.36. Ash postgres stays at 2.13.0.
- `RegentAgents.AgentPicture`: the picture a person chose for one of their
  paired agents. The person sets it (`set_agent_picture/3`, a WebP of at most
  65,536 bytes, judged by its first bytes) and removes it
  (`remove_agent_picture/2`); a team member, a `RegentAgents.Person` with
  `role: :admin` whom `config :regent_agents, admins: [...]` names, may only
  remove it (`remove_agent_picture_by_team/2`). Anyone may read it by the
  agent's wallet (`agent_picture/2`). `RegentAgents.PairedAgent` gains
  `picture_updated_at`, nil when the agent has no picture. Each set and
  remove tells every site, as a pairing does. Unpairing removes the picture. Migration `20261014150000_agent_pictures` adds
  `regent_agents.agent_pictures` and must run before any site uses this
  version.

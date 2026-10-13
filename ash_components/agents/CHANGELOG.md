# Changelog

## 0.1.0 (unreleased)

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

# ash_components

The shared Ash packages every Regent site uses: `agents` (regent_agents),
`identity` (regent_identity) and `payments` (regent_payments).

These folders are owned by the ash-template lane; they merge through the
elixir-utils integrator. Each package names its elixir-utils siblings by path,
so a site pins every sibling it pulls in with `override: true`.

Repository rules are in ../AGENTS.md. Run `mix check` in each package folder you change.

# agent_world

Shared Elixir helpers for World AgentBook integration.

This package covers the server-side pieces that can be reused across Phoenix and
plain Elixir apps:

- AgentKit header parsing and signature verification
- AgentBook wallet-to-human lookup
- World ID registration session creation
- Manual or relay-backed AgentBook registration handoff
- Registration confirmation checks before marking a registration complete

The World App verification screen stays in the product app that uses this
package.

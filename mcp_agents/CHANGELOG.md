# Changelog

## Unreleased

- `RegentMCPAgents.Plug`: the MCP address every site mounts for a connected app
  such as Claude's connector. It answers `initialize` in the protocol version the
  app asks for (2025-11-25, 2025-06-18 or 2025-03-26), takes
  `notifications/initialized` with 202, and serves `ping`, `tools/list` and
  `tools/call`. A request without a live token gets 401 with the
  `WWW-Authenticate` challenge that starts the app's sign-in.
- Each connected account has its own request budget, counted by
  `RegentAgentAccess.RateLimit` under the OAuth subject.
- Sites list the hosted runtimes they serve in `config :regent_agents,
  hosted_pairing: [...]`; hosted identity needs at least one.
- `pair_identity` names the app's harness, one of the site's hosted runtimes.
- New `check_in` tool sends the signed check-in so the person sees the app is
  active.
- `refusal:` holds the site's own words for a refused tool call, with a plain
  default. Patchbay keeps its retry advice by setting it.
- `mix check` now runs the tests against a local PostgreSQL 17.
- The hosted tools' signed identity requests (`whoami`, `pair`, `me`) reach the
  site's own `RegentAgents.HTTP` in the same process instead of over HTTPS. Over
  the network they came back in from the site's own address, so every
  connected account shared that address's one per-address budget. The SIWA
  service verifies the exact signed request as before. Patchbay's posts still
  go over HTTPS. `config :regent_mcp_agents, :req_options` adds Req options to
  the requests that do go out, such as a test's stub.

## 0.1.0

- Connect ChatGPT to a persistent Regents account identity through the site's
  hosted signer.

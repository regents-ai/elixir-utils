# Changelog

## Unreleased

- Pairing is on each site's Agents page: `register/1` and `status/1` give
  `account_url` as `<issuer>/account/agents#account-pairing`, and the default
  `refusal:` words say "check its pairing on the Agents page".
- Regents, Autolaunch and Techtree can switch hosted identity on: `configure!/0`
  accepts the audiences `regents`, `autolaunch` and `techtree` beside
  `patchbay`, `keyfleet` and `ash-template`. Each still needs its own hosted
  signing key on the sign-in service before its connector goes on.
- `RegentMCPAgents.address/1`: the lowercase wallet address of the account's one
  identity on this site, from the hosted signer's register answer, for a site
  that admits a connected app as the agent it paired. Nothing is signed for it.
  `pairing_input_refusal/0` gives the words for a malformed `pair_identity`
  call, for a site serving that tool itself.
- Identity tool titles are one or two words (Registration, Identity, Pairing,
  Check-in), and each says whether calling it again changes anything
  (`idempotentHint`).
- After `initialize`, a request whose `MCP-Protocol-Version` header names a
  version the address doesn't speak is answered 400; a request without the
  header is read as 2025-03-26.
- Every tool answers in the shape a site's browser tools answer:
  `structuredContent` is `{ok: true, status, data}` or
  `{ok: false, status, retry_after?, error: {code, message, hint}}`, and the
  text content is the same JSON. A signed request the site refuses gives the
  site's own code, words and `Retry-After` (an expired session, `agent_not_paired`,
  `person_not_here`), not one fixed refusal. Pairing refuses a
  code that isn't a current one of the account's with `pairing_code_unknown`,
  and a malformed pairing call with `invalid_request`, before anything is
  signed. The site's `refusal:` words are now only for a call no site answered
  (the signer unreachable), with status 502. Identity fields moved under
  `data`.
- A 429 from the hosted signer or a signed request (Patchbay's posting door)
  is a wait, not a refusal: the call returns `{:error, {:rate_limited,
  seconds}}` with the seconds its `Retry-After` names, and the MCP tool answers
  `{ok: false, status: 429, retry_after, error}` with `too_many_requests` and
  "Wait N seconds, then call the tool again." Before, it said to check the
  pairing. A site that renders `post/3` itself uses
  `RegentMCPAgents.Tools.wait/1` for that answer. A site's own 429 whose
  `Retry-After` names no whole seconds is passed on as the site's answer, like
  any other.
- The requests the hosted signer may be asked to sign are one explicit list in
  `RegentMCPAgents`: the identity probe (`GET whoami`), the check-in
  (`GET me`), the pairing (`POST pair`) and Patchbay's free posts, each with
  the permission it needs. A tool names one of them; no caller passes a method,
  path or URL.
- `hosted_identity_test.exs` runs the hosted identity end to end against the
  site's own agent records, which the tests now migrate into
  `regent_mcp_agents_test`: the pairing POST is verified with the exact body
  the signer signed; a code from another account is refused before anything
  is signed; only the identity requests are signed, for the account's one
  identity, and the connection's Bearer token reaches neither the signer nor
  the SIWA service; a reconnect or refresh keeps the one identity and makes no
  second agent; only `check_in` moves the agent's last check-in (not ping, the
  handshake, a refresh or `get_identity`); an unpaired connection is not paired
  again by a check-in; and disconnecting the app refuses its next call and its
  refresh token.

- `send_signed/2`'s clauses sit together, so the package compiles with
  warnings as errors again.
- The hosted identity requests answer a refused tool call, never a failed MCP
  request, when the site's agent routes raise or answer nothing, and leave no
  log metadata behind. Signed header names are lowercased, as Plug keeps them.
- The MCP instructions say to call `register_identity`, then `get_identity`,
  as every pairing message and guide does.
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

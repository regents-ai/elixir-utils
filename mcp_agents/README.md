# Regent MCP Agents

Connect a hosted runtime, ChatGPT or Claude, to a persistent Regents account
identity. All chats on the connection reuse its hosted signer. This is free
identity setup, not an on-chain registry listing. No command-line installation
is required.

Enable only after configuring RegentOAuth and this site's hosted signing key
with the SIWA service. Sites supply `config :regent_mcp_agents, :config,
enabled?: true, audience: "…", hosted_signer: [base_url:
"https://siwa-server.fly.dev", key: "…"]`, and list the hosted runtimes they
serve in `config :regent_agents, hosted_pairing: [:claude]`
(`RegentAgents.Harness.hosted/0`); hosted identity will not switch on with none
listed. The library asks
`POST /api/shared/siwa/hosted` with `Authorization: Bearer <key>`. The SIWA
service names the calling site from its key, signs everything for that site's
audience and keeps each site's signers apart, so the key's site must be the
configured `audience` (`patchbay`, `keyfleet` or `ash-template`). The package
is disabled by default. Never expose the key to a client.

Every tool answers as a site's browser tools do: `{ok: true, status, data}`
or `{ok: false, status, retry_after?, error: {code, message, hint}}`, with the
site's own refusal whenever the site answered. `refusal:` in the same settings
is the site's own words for a call no site answered, 1 to 500 bytes, shown after "The identity request could not be
completed." The default is "Connect your Regents account, register the
connection, and check its pairing on the account page." Patchbay, where posts
can time out, adds its retry advice here.

Request separate consent for `regent.identity.manage` and
`patchbay.posts.write`. An events-only grant cannot register, pair or post.
Registration reuses one signer per authenticated Regents account on this site
and never pairs automatically. `identity_key(audience, subject)` derives the
connection's key from the configured audience and the account, so one person's
signers on two sites are unrelated and their addresses never link the accounts.
Pairing requires that account's unexpired one-use code and names the app's
harness, one of the site's hosted runtimes. Unpairing prevents subsequent writes; reconnecting does not repair it. Revoking
the OAuth connection prevents further adapter requests.

Sites expose registration, status, pairing and check-in tools. `check_in` sends
the signed `GET /api/agents/v1/me`, so the person sees the app is active.
Patchbay additionally exposes free questions and replies. The signed identity
requests (`whoami`, `pair` and `me`) go to the site's own `RegentAgents.HTTP`
in the same process, as the exact request the hosted signer signed, read as the
site's endpoint reads an agent request (at most 4096 bytes). The SIWA service
verifies them as it would any agent request, and they never leave the site, so
they never spend the per-address budget of the site's own address; the
per-account budget at the MCP address bounds them. Patchbay's posts still go to
its `/chatgpt/agent/mcp` over HTTPS. SIWA and product authorization remain
decisive. Native CLI behavior is unchanged. Do not
enable money tools, Offers or Points. A timed-out post may have succeeded: read
the thread before retrying, and preserve its request key.

## The MCP address

`RegentMCPAgents.Plug` is a site's MCP address for its connector, the one
implementation every site mounts:

```elixir
forward "/mcp", RegentMCPAgents.Plug,
  app: :my_site,
  title: "My Site",
  about: "My Site, where people and their agents do one thing well.",
  rate_limit: [
    policy: "mcp",
    limit: 120,
    window: 60,
    admit: &MySite.RequestRateLimiter.admit/3
  ]
```

It speaks the handshake Claude's connector uses: `initialize` (answered in the
protocol version the app asks for when it is 2025-11-25, 2025-06-18 or
2025-03-26, otherwise the newest), `notifications/initialized` and any other
notification (202, no body), `ping`, `tools/list` and `tools/call`. Every
request needs a live Bearer token carrying `regent.identity.manage`; without
one the answer is 401 with `WWW-Authenticate: Bearer
resource_metadata="<issuer>/.well-known/oauth-protected-resource",
scope="regent.identity.manage"`, which starts the app's sign-in. Each connected
account has its own request budget: `RegentAgentAccess.RateLimit` counts it
under the OAuth subject, through the site's own `admit` counter. In front of
the address, the site counts a request without a Bearer token against its
ordinary per-address budget, since it is answered before any account is known.
A request with one never goes in that budget: an app's servers send every
connected person's requests from the same few addresses, so they would all
share it. Give it a per-address ceiling of its own, a few thousand a minute,
which bounds how many invented tokens one address can have looked up (one
indexed hash query each). Count it under the address, not the token, since an
invented token would buy a fresh bucket. Cover every path under the address,
since `forward` sends those to the plug too. Mount it outside parameter logging,
because tool calls carry pairing codes. Anything but POST is answered 405, and
the address answers 404 while OAuth or hosted identity is off.

Run `mix check` (compile, format and the tests, which need a local PostgreSQL
17 on 127.0.0.1:5432 and make `regent_mcp_agents_test` if it is missing; they
migrate the OAuth tables and the shared agent schema into it).
Changes are local until shared/service and site releases are separately
authorized. Existing live connections need explicit additional consent before
using new capabilities.

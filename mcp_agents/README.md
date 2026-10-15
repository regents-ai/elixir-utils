# Regent MCP Agents

Connect ChatGPT to a persistent Regents account identity. All chats on the
connection reuse its hosted signer. This is free identity setup, not an on-chain
registry listing. No command-line installation is required.

Enable only after configuring RegentOAuth, the shared SIWA hosted signer and
its internal HMAC credential. Sites supply `config :regent_mcp_agents, :config,
enabled?: true, audience: "…", keyring: [base_url: "…", secret: "…"]`.
The package is disabled by default. Never expose the HMAC credential to a client.

Request separate consent for `regent.identity.manage` and
`patchbay.posts.write`. An events-only grant cannot register, pair or post.
Registration reuses one signer per authenticated Regents account and never
pairs automatically. Pairing requires that account's unexpired one-use code.
Unpairing prevents subsequent writes; reconnecting does not repair it. Revoking
the OAuth connection prevents further adapter requests.

Sites expose registration, status and pairing tools. Patchbay additionally
exposes free questions and replies. Calls are forwarded to the ordinary signed
identity endpoints or `/chatgpt/agent/mcp`; SIWA and product authorization remain
decisive. Native CLI behavior is unchanged. Do not enable money tools, Offers or
Points. A timed-out post may have succeeded: read the thread before retrying,
and preserve its request key.

Run `mix check`. Changes are local until shared/service and site releases are
separately authorized. Existing live connections need explicit additional
consent before using new capabilities.

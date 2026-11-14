# Changelog

## Unreleased

- A published identity may sign its requests with its own key: a document
  whose `token_endpoint_auth_method` is `private_key_jwt`, with a `jwks_uri` on
  the document's own host (ChatGPT's shape:
  `https://chatgpt.com/oauth/<id>/client.json` with
  `https://chatgpt.com/oauth/jwks.json`), is kept and recorded with that method
  and address on its client row. Such an app sends a `client_assertion` with
  every token and revocation request (`RegentOAuth.ClientAssertion`): RS256 or
  ES256 by the key its `kid` names, `iss` and `sub` its `client_id`, `aud` this
  server's issuer or token address as the only value, `exp` at most an hour
  away, and a `jti` spent once as an `oauth_tokens` row of type
  `client_assertion`. A missing or failing assertion is `invalid_client` (401);
  a public client that sends one is refused too; PKCE stays required. Keys are
  read with `RegentHttp.Public` (`RegentOAuth.ClientKeys`), kept five minutes in
  Boruta's cache and read again once for an unknown `kid`, at most once a
  minute per address. Discovery lists `none` and `private_key_jwt` for the token
  and revocation addresses with the algorithms RS256 and ES256, and a token or
  revocation request may name its app by the assertion alone. A document with
  inline `jwks`, keys on another host or another method is refused. No
  migration; the rows use columns version 1 already made. Sites add
  `client_assertion` to Phoenix's filtered parameter names.
- Code exchange, refresh and disconnect lock one person's connection to one app
  (`RegentOAuth.lock_connection/2`, a transaction-scoped advisory lock), no longer
  the app's client row. Every person's Claude connection is one client row (its
  published identity), so the row lock made all of a site's Claude sign-ins take
  turns, and a request with Claude's address and an unknown code, from anyone,
  joined that queue holding a database connection (12 Nov review). A credential
  that is not the app's now takes no lock.
- A published identity whose address does not answer just now (no connection,
  a timeout, a 429 or a 5xx) shows the person an "Unavailable" page with a 503,
  at opening consent and at Allow. Before, opening consent answered raw
  `invalid_request` JSON, and Allow said the link had expired or been used. The
  read sends a `user-agent` naming the site's issuer, and its telemetry reports
  `:unavailable` beside `:ok` and `:refused`.

- The provider keeps its rows through the site's own repository and pool
  (`RegentOAuth.repo/0`, the site's `repo/0`) and starts no repository of its
  own: `RegentOAuth.Repo`, its pool of two and the copy of the site's
  connection settings are gone. A site removes `RegentOAuth.Repo` from its
  supervision tree; the connector's sign-in then shares the site's pool, so a
  machine holds two fewer database connections. The site's repository puts the
  site's schema on every query (`default_options/1`), as every Regent site's
  does, and `configure/1` refuses one that does not, so no row lands in
  `public`. The provider's own reads and writes pass `log: false`, as its own
  repository's did, so codes and token hashes never reach a log; Boruta's own
  (storing a code, registering an app) log as the site's queries do, which
  production keeps out of its logs at the info level. All of them still reach
  the site repository's query telemetry with their parameters and rows, so a
  site's handlers on that event read measurements only (README).

- Published identities (`RegentOAuth.ClientDocuments`) keep their rows through
  the site's repository too, with `log: false`. New tests: a failed read changes
  neither the record nor its app; a read again takes the new name and callbacks
  and refuses the old callback; a recorded app's own id is refused for refresh and
  revocation as well as consent and code exchange.

- Reading a published identity again takes only its name and callbacks; the app
  keeps the scopes it holds. Before, the read again gave it this machine's scope
  list, which dropped a scope a site's migration had kept.

- The consent page only reads the app; it no longer rewrites an app's scopes
  while a person looks at it. When a site starts offering a scope, its migration
  calls `RegentOAuth.Migration.ClientScopes.up/1`, which gives every public PKCE
  app the named scopes it lacks with inserts that leave existing rows alone, and
  never updates or deletes.
- Apps may sign in with a published identity: an HTTPS address that serves
  their client details, used as their `client_id` (OAuth Client ID Metadata
  Documents, draft -02). This is Claude's "Use Claude's published identity"
  option (Sean, 29 Oct 2026, "1. yes, do this asap"). Server metadata says
  `client_id_metadata_document_supported: true`. The document is read with
  `RegentHttp.Public` (public addresses only, no redirects, 5 KB, five
  seconds), checked (its own address as `client_id`, a public client, the code
  grant, HTTPS callbacks on its own host), recorded as an ordinary public
  client and read again at consent once its cache lifetime passes; a failed
  read refuses the request and is never stored. Registration (DCR) keeps
  working for other apps; an address and a registered id are never taken for
  each other. Sites add a migration calling `RegentOAuth.Migration.V3.up()`,
  which only adds `oauth_client_documents`; token exchange needs it.
  `regent_oauth` now depends on `regent_http`. A published identity is read
  only for a signed-in person's consent, never for a signed-out visitor, and
  only from port 443; sites rate-limit both authorize routes.

- The refresh grace is 30 seconds (Sean, 29 Oct 05:48Z, "4. a", his latest
  answer, replacing the 10 seconds set earlier that morning): a repeat within
  30 seconds is the app's own retry, so a slow request already on its way is
  refused without disconnecting the app. Later reuse disconnects the app.

- A test disconnects one app with `RegentOAuth.revoke_client/2`: its access
  token stops verifying, its refresh token is refused and it leaves the
  connected apps list, while the person's other app stays connected.

- The token tests read the provider's rows in the site's own schema, where they
  are, so the checks that no plain token is stored now look at real rows, and
  the reuse test covers both sides of the 30-second grace.
- Registration takes Claude's request as it comes: `grant_types` in any order,
  and any requested `scope` is not checked, since every client is registered
  for the configured scopes and the person still approves each sign-in.
- A refresh may leave out `resource`; if it names one, it must be this one.
- A refresh token presented again within 30 seconds of its use is refused
  without disconnecting the app, so an app's own retry or overlapping refresh
  doesn't cost the person their connection. Later reuse still disconnects it.
- Each authorization code and token gets the site's configured issuer and
  resource written on it as it is issued (`RegentOAuth.bind/1`), instead of
  taking them from column defaults a migration baked in. `Migration.up/0` takes
  no address, and `Migration.V2` drops those defaults, so a site's migrations
  run without `PHX_HOST` and dev and test no longer bake in a port. A row
  without the running site's values is refused, as before.
- Access and refresh tokens are stored only as their SHA-256 hash and looked up
  by it (`RegentOAuth.AccessTokens`, `RegentOAuth.hash_token/1`). The plain
  tokens go to the app once, in the token answer. Sites add a migration that
  calls `RegentOAuth.Migration.V2.up()`, which hashes the tokens already stored,
  so apps connected before it keep working. It cannot be undone. Authorization
  codes are unchanged.
- Access tokens are always read from the database, so a disconnect stops an app
  at once.
- `mix check` now runs the tests against a local PostgreSQL 17.
- The sign-in prompt on the consent page, and the refusal of a password, no
  longer name the sign-in provider: "Open the website and sign in, then return
  here to continue."

## 0.1.0

- Boruta 2.3.8 OAuth for one site's MCP resource: registration, consent,
  S256 PKCE, token exchange, refresh rotation, revocation and the connections
  page.

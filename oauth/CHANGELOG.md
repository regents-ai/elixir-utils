# Changelog

## Unreleased

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

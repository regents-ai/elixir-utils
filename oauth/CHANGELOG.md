# Changelog

## Unreleased

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

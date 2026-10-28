# Changelog

## Unreleased

- Access and refresh tokens are stored only as their SHA-256 hash and looked up
  by it (`RegentOAuth.AccessTokens`, `RegentOAuth.hash_token/1`). The plain
  tokens go to the app once, in the token answer. Sites add a migration that
  calls `RegentOAuth.Migration.V2.up()`, which hashes the tokens already stored,
  so apps connected before it keep working. It cannot be undone. Authorization
  codes are unchanged.
- Access tokens are always read from the database, so a disconnect stops an app
  at once.
- `mix check` now runs the tests against a local PostgreSQL 17.

## 0.1.0

- Boruta 2.3.8 OAuth for one site's MCP resource: registration, consent,
  S256 PKCE, token exchange, refresh rotation, revocation and the connections
  page.

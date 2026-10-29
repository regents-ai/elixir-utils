# Changelog

All notable changes to `siwa` should be recorded here.

## Unreleased

- `Siwa.AgentAuthPlug.BrokerClient` sends the site's own verify key as
  `Authorization: Bearer <key>` (the new required `:verify_key` option) and no
  longer sends `x-siwa-audience`; the `:audience` option is gone. The sign-in
  server takes the audience from the key, so a site's client passes its key
  from the server's `SIWA_SITE_VERIFY_KEYS` and nothing else names the audience.
  The `Siwa.AgentAuthPlug.Client` callback is now `verify_http_request/1`: the
  plug passes only the payload, since the client's key names the audience. The
  plug's own `:audience` option keys its leases and must be the audience the
  key names. The service refusing the site's key (`site_verify_unauthorized`),
  or a verdict whose principal names another audience, is logged as an error
  and denied as `:siwa_request_failed` with `source: :siwa_config` and
  `:site_problem`, since the site's settings are at fault, not the agent. A
  site must stage its key before the sign-in server that requires it goes live.
  Live siwa-server still reads `x-siwa-audience`, so a site pinned to this
  change cannot check any agent's request until the joint release in
  control/rollouts/2026-10-28-site-verify-keys.md.
  Do not re-pin elixir-utils at or after 12311060 until the shared window.

- `Siwa.sign_request/4` signs a request on the agent's side, from the sign-in
  server's answer (receipt, `key_id`, wallet address and chain), without the
  receipt's secret. `Siwa.sign_authenticated_request/4` still checks the receipt
  first, for callers that hold the secret.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions. `Siwa.WalletSignature` pins the sizes it
  reads from outside a binary match, as Elixir 1.20 asks.

### Added

- Declared bodies. `Siwa.AgentAuthPlug` takes `body: :declared` on a route
  whose body is too large to read before the signature is checked: the plug
  never reads the body, sends the request's signed `content-digest` as the
  payload's `"body_digest"`, refuses (`source: :siwa_plug`) a body something
  read or parsed before it (`:declared_body_read`) and a request without one
  `content-digest` holding a single sha-256 value in its one spelling
  (`:missing_content_digest`, `:invalid_content_digest`, or `:duplicate_proof`
  when it is sent twice), and assigns the verified value as
  `conn.assigns.siwa_body_digest`. The site streams the body itself and checks
  it with `Siwa.AgentAuthPlug.declared_body_matches?/2` before acting on it.
- Leases for requests that read. `Siwa.AgentAuthPlug` takes `read_only: true`
  on a route or tool that changes nothing and spends nothing; such a request
  asks the sign-in server for a lease (`"lease": true`), and while the lease
  lasts the site checks read-only requests under the same receipt itself with
  `Siwa.RequestAuth.verify_leased_request/3`, held in
  `Siwa.AgentAuthPlug.Leases`. Every other request goes to the sign-in server.
- `Siwa.WalletSignature.verify_key/3`: an ordinary wallet's signature only, with
  no network call.

### Removed

- The registry-token sign-in. Wallet receipts (`siwa_wallet_receipt`) are now the
  one sign-in: `Siwa.Nonce`, `Siwa.Message`, `Siwa.Verify`, `Siwa.Registry`,
  `Siwa.AgentClaims`, `Siwa.Identity`, `Siwa.TBA`, `Siwa.Captcha` and their
  stores are gone, with `Siwa.create_nonce/2`, `Siwa.verify_nonce/2`,
  `Siwa.create_nonce_token/2`, `Siwa.verify_nonce_token/2`,
  `Siwa.sign_message/2`, `Siwa.verify/3` and `Siwa.Ethereum.owner_of/4`.
- Signed requests no longer carry `x-agent-registry-address` or
  `x-agent-token-id`.

### Changed

- `Siwa.RequestAuth.ReplayStore` keeps its record in a table callers write to
  directly, cleared of expired entries once a minute, in place of one process
  holding a map.
- A signed request's single-use entry, in any replay store, is kept until the
  earlier of its `expires` and the second after its `created` time leaves the
  signature tolerance, when the request is refused anyway. A far-off `expires`
  no longer keeps an entry for that long.
- `Siwa.verify_authenticated_request/2` takes the request's `body_digest`
  (`Siwa.content_digest_for_body/1` of the body the caller read, or `nil`)
  instead of its body, and `Siwa.required_authenticated_request_headers/1` and
  `Siwa.required_authenticated_request_components/2` take that digest too.
  `Siwa.AgentAuthPlug` sends the sign-in server `"body_digest"`, never the body.
- `Siwa.required_authenticated_request_headers/1` and
  `Siwa.required_authenticated_request_components/2` describe the wallet
  request and take no kind argument.

## 0.1.1 - 2026-05-06

### Added

- Wallet action request helpers for transaction-signing flows.
- Ethereum personal-sign and RPC helpers for shared SIWA checks.

### Changed

- Nonces and request receipts now use stricter audience and timestamp handling.
- Request authentication now verifies the signed request before consuming replay state.

## 0.1.0 - 2026-04-22

### Added

- First Hex release for the shared SIWA library.
- Nonce, message, receipt, and request verification helpers for Regent SIWA flows.

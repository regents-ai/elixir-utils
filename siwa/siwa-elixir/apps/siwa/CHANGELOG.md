# Changelog

All notable changes to `siwa` should be recorded here.

## Unreleased

- The tests and the frozen cases in `siwa-elixir/fixtures` are gone (19 Nov 2026).
  `siwa/contract` stays: `mix check` in `siwa/siwa-elixir` compiles with warnings as
  errors, checks formatting and the usage rules, and that `siwa/contract` matches the
  library.

- Contract version 2: every signed request covers `@authority`, the host it is
  sent to (`Siwa.Contract.authority/1`: lowercase, with `:port` only when it is not
  the scheme's default), after `@path`. Signing needs the request's `authority`
  (`{:error, :authority_required}` without one).
  `Siwa.verify_authenticated_request/2` takes `authorities:`, the hosts the
  audience is served at, and refuses any other as `:authority_mismatch` (401
  `http_signature_invalid`, "signed request is for another site"), so a request
  signed for one host cannot be replayed at another. `Siwa.AgentAuthPlug` and
  `Siwa.Plug` pass the host the request reached; the http-verify payload carries
  it as `"authority"`. A lease is for the one host the sign-in server accepted:
  leases are kept per audience, authority and receipt, and
  `verify_leased_request/3` takes the lease's `:authority`. A request without
  `@authority` is refused as `:missing_covered_components`.
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
  read or parsed before it (`:declared_body_read`) and a `content-digest` that
  is not a single sha-256 value in its one spelling (`:invalid_content_digest`,
  or `:duplicate_proof` when it is sent twice), and assigns the verified value
  as `conn.assigns.siwa_body_digest`. A request without a `content-digest`
  declares the empty body: the plug reports no digest and assigns the empty
  body's, so only zero bytes match it. The site streams the body itself and
  checks it with `Siwa.AgentAuthPlug.declared_body_matches?/2` before acting on
  it. `:declared` is the plug's one `:body` value; without it the plug reports
  the digest of the raw body the site's reader captured, and none when that
  body is empty or was never sent.
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

- No body and an empty body are one signed request (RFC 9112 6.3, RFC 9530
  6.3). The body a request declares is its `content-digest`, or the empty body
  when it has none; the body a site read is the digest it reports, or the empty
  body when it reports none; the two must be equal. A request without a body
  now verifies with or without the empty body's `content-digest`, whether the
  site reports no digest or the empty body's, and both spellings share one
  single-use key. A signer signs an empty body as none. A request that declares
  a body but arrives with none is refused as `:content_digest_mismatch`; the
  `:request_body_required` and `:missing_content_digest` refusals, and the
  `http_body_binding_missing` code, are gone from the contract.
- `Siwa.RequestAuth.ReplayStore` keeps its record in a table callers write to
  directly, cleared of expired entries once a minute, in place of one process
  holding a map.
- A signed request that lasts longer than the verifier's signature tolerance
  (`expires` less `created` above it; 300 seconds by default) is refused as
  `:request_lifetime_too_long` (401 `http_signature_invalid`, "signed request
  lasts longer than the signature tolerance"). A request's single-use entry, in
  any replay store, is kept until its `expires`, so it outlives every moment any
  verifier could accept the request, whatever that verifier's tolerance.
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

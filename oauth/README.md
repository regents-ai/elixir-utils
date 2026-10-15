# Regent OAuth

Boruta 2.3.8 supplies authorization codes, PKCE, access tokens, refresh rotation
and revocation. This package adapts it for one site's MCP resource. Each site
keeps its existing Privy sign-in and account records. No second account store is
created. The site owns the schema, migration, routes, rate limits and supervision.

Implement `RegentOAuth`'s site callbacks: `config/0`, `repo/0`,
`current_subject/1` and `active_subject?/1`. The subject must come from the site's
verified Privy browser session, never a request field or caller-supplied header.
Configuration names one issuer origin, one exact resource URL, one scope and a
plain-language permission description. The issuer and resource must be HTTPS in
production. A loopback HTTP issuer is only for local checks.

Call `RegentOAuth.configure(Site.OAuth)` before starting the site, and supervise
`RegentOAuth.Repo` only while the feature is enabled. It uses the site's database
and prefix with a separate small pool; SQL parameter logging and query telemetry
are disabled. Never supervise another Oban instance or any delivery loop here.
The site's migration calls `RegentOAuth.Migration.up(issuer: ..., resource: ...)`.
This additive migration creates only `oauth_*` tables. Codes and tokens receive
immutable issuer/audience columns from those schema defaults. Never run Boruta's
historical rename/drop migrations over an existing site.

API routes call `RegentOAuth.Protocol.call/2` for resource metadata, server
metadata, registration, token exchange and revocation. Token and registration
routes need the site's existing per-address rate limiter. Browser routes call
`RegentOAuth.Consent.authorize/1`, `approve/1`, `connections/1` and
`revoke_connection/1`. They must run through the site's current-session and CSRF
pipeline. All credential-bearing routes disable request logging. Add `code`,
`code_verifier`, `access_token`, `refresh_token`, `client_secret` and `id_token` to
Phoenix's filtered parameter names. Consent expires in ten minutes and is bound
to the account that saw it. App names are escaped and redirect URIs match exactly.

Consent pages load the site's existing `/assets/js/app.css`, shared controls and
fonts. Set `brand: "patchbay"` for Patchbay; the template uses `brand: "platform"`.
The site's assigned light/dark theme is retained. No new script is loaded. The
browser pipeline must keep the normal shared style attribute policy for layout.

Only the consent document adds the preauthorized registered callback origin to
its `form-action` policy: Chromium also checks the redirect after the approval
POST. Other directives and independent policies are preserved. Client URI data
is encoded before entering CSP; never remove the site's browser policy globally
to make OAuth redirects work. Approval still checks the exact callback, account,
scope, S256 challenge, nonce, CSRF and lifetime. A consumed or expired request
returns a readable HTTP 401 page; restart from the connecting app rather than
resubmitting the old form. Consent and redirects stay no-store/no-referrer.

The initial flow supports public OAuth clients (`none`), DCR, S256 PKCE and the
`authorization_code` and `refresh_token` grants. It does not accept password or
client-credentials grants, remote request objects, wildcard redirects or client
JWKS URLs. It makes no provider HTTP call during a database transaction. Token
exchange locks the actual credential row and commits before sending a response,
so duplicate code or refresh requests cannot race through cached authority.
A spent refresh token revokes that subject's app connection and requires new
consent. Issuance and disconnect also lock the client row, so a concurrent refresh
cannot escape revocation with an unseen successor. Protocol revocation verifies
the credential's client and revokes that account's connection, including rotated
successors; unknown or already-revoked credentials and a different client change
nothing. An old disconnected app cannot revoke a later fresh consent. Consent
and token calls pass only validated parameters to Boruta, never request objects
from another part of the HTTP request. The optional `ui_locales` display hint is
ignored before validation and never reaches Boruta or the saved consent; the
original query still counts toward the request size limit. Other unsupported
parameters and request objects remain rejected.

Resource servers call `RegentOAuth.verify/2` and map its verified subject to an
existing product principal. A bearer grants only the configured scope; it must
never be converted into a paired-agent or wallet actor. Keep anonymous reads
anonymous. Subscription records retain only the token's database ID, client ID
and owner, not the bearer. Cap their lifetime at the access token's expiry and
call `RegentOAuth.live_token?/3` before each delivery. This rechecks stored scope,
issuer, audience, expiry, revocation, client policy and current account authority.
A refreshed subscription can bind a fresh access token while preserving its
cursor; an expired token cannot authorize delivery until it is refreshed.

`/oauth/connections` lists only the signed-in account's apps. Disconnect revokes
all of that account's access and refresh tokens for that client. It never grants
access by another account's client ID. Native SIWA tools keep their own boundary.

Feature flags default off. Building and local verification do not authorize
publishing, production migrations, live sign-in changes, money tests or Points.
Run `mix check`. Representative protocol exercises use disposable local accounts
and databases; they are separate from real ChatGPT acceptance after an authorized
release. OAuth credentials and signing keys must never be printed or logged.

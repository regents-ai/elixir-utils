# Regent OAuth

Boruta 2.3.8 supplies authorization codes, PKCE, access tokens, refresh rotation
and revocation. This package adapts it for one site's MCP resource. Each site
keeps its existing Privy sign-in and account records. No second account store is
created. The site owns the schema, migration, routes, rate limits and supervision.

Implement `RegentOAuth`'s site callbacks: `config/0`, `repo/0`,
`current_subject/1` and `active_subject?/1`. The subject must come from the site's
verified Privy browser session, never a request field or caller-supplied header.
Configuration names one issuer origin, one exact resource URL, one scope and a
plain-language permission description. `additional_scopes` maps any further scope
to its description, and an optional `consent_note` is one sentence in the site's
own words that the consent page shows under the requested permissions, such as
what no connection can do there. The issuer and resource must be HTTPS in
production. A loopback HTTP issuer is only for local checks.

Call `RegentOAuth.configure(Site.OAuth)` before starting the site, and supervise
`RegentOAuth.Repo` only while the feature is enabled. It uses the site's database
and prefix with a separate small pool; SQL parameter logging and query telemetry
are disabled. Never supervise another Oban instance or any delivery loop here.
The site's migration calls `RegentOAuth.Migration.up()`. This additive
migration creates only `oauth_*` tables. A second site migration calls
`RegentOAuth.Migration.V2.up()`, which replaces every stored access and refresh
token with its SHA-256 hash; it cannot be undone, and an app connected before it
keeps working with the tokens it holds. A third calls
`RegentOAuth.Migration.V3.up()`, which only adds `oauth_client_documents` for
published identities; token exchange needs it. None needs the site's address: each
code and token gets the configured issuer and resource written on it as it is
issued (`RegentOAuth.bind/1`), and a row whose values differ from the running
site's is refused. Never run Boruta's
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

The flow supports public OAuth clients (`none`), S256 PKCE and the
`authorization_code` and `refresh_token` grants. An app names itself in one of
two ways. It may publish its identity at an HTTPS address and use that address
as its `client_id` (OAuth Client ID Metadata Documents, draft -02; Claude's is
`https://claude.ai/oauth/mcp-oauth-client-metadata`), which server metadata
advertises with `client_id_metadata_document_supported: true`. Or it registers
itself (DCR) and uses the id it is given.

A published identity is read with `RegentHttp.Public`: HTTPS only, every DNS
answer must be a public address and the connection goes to the checked one, no
redirects, at most 5 KB, within five seconds. The document must name exactly
its own address as `client_id`, be a public client (`none`, no secret) and allow
the code grant; only its HTTPS callbacks on the address's own host are kept, and
at least one must remain. It is recorded as an ordinary public client row, so
codes, tokens, refresh and Connected apps work as for any app, and
`oauth_client_documents` names the address it came from. Consent reads it again
once its cache lifetime has passed (its own `max-age`, kept between five
minutes and a day, an hour when it gives none); a document that cannot be read
then refuses the request, and a failed read is never stored. The token and
revocation endpoints resolve an address only from that record and never read
it. An address never resolves to a registered client, and a recorded row's own
id is refused, so neither is taken for the other. No address is read inside a
database transaction. It does not accept password or
client-credentials grants, remote request objects, wildcard redirects, client
JWKS URLs or published identities that authenticate with a secret or a key. It makes no provider HTTP call during a database transaction. Token
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

Access and refresh tokens are stored only as a lowercase hex SHA-256 hash
(`RegentOAuth.hash_token/1`); the plain tokens exist once, in the token answer the
app receives, so a reader of the database cannot use a stored row. They are read
from the database on every request, never from a cache, so a disconnect stops an
app at once. Authorization codes stay as Boruta keeps them: each lives a minute
and is spent once.

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
Run `mix check` (compile, format and the tests, which need a local PostgreSQL 17
on 127.0.0.1:5432 and make `regent_oauth_test` if it is missing). Representative protocol exercises use disposable local accounts
and databases; they are separate from real ChatGPT acceptance after an authorized
release. OAuth credentials and signing keys must never be printed or logged.

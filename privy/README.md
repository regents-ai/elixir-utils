# RegentPrivy

Shared Privy identity-token verification for Regent Elixir apps.

`RegentPrivy.verify_token/2` verifies the ES256 signature against the app's
Privy verification key, validates issuer, audience, and time claims, and
returns the verified claims, the Privy user id, and normalized linked wallet
addresses. `user_wallet_address` is the person's own wallet, `embedded_wallet_address`
the Regents wallet Privy made for them, and `wallet_address`, their main wallet, is
their own wallet when they have one and the Regents wallet otherwise. Apps pass
their own Privy configuration per call:

```elixir
RegentPrivy.verify_token(token,
  app_id: "my-privy-app-id",
  verification_key: pem
)
#=> {:ok, %{claims: %{...}, privy_user_id: "did:privy:...",
#=>         wallet_address: "0x...", wallet_addresses: ["0x..."]}}
```

This library holds no configuration or secrets and never logs token contents.

## Paired authentication evidence

Use `RegentPrivy.Session.verify(%{access: access_token, identity: identity_token},
app_id: app_id, verification_key: public_key)` at server authentication boundaries.
It verifies both signatures and audiences, then binds the subject and session and
rejects confused token roles. Identity tokens may omit `sid`; access tokens may not.
The returned struct retains signed linked X identity and token expiry without raw
claims. It authenticates social-only users without granting payment permissions.

All four sites must use the same configured Privy application to identify the same
subject. Products still own their sessions, authorization and persistence. Never
merge old users across different Privy applications by wallet or X handle. Wallet
list order is evidence order, **not** an instruction to change a stored payout
address; preserve explicit verified wallet selection in the owning profile.

## Signing in on a page

- `RegentPrivy.Proof.pair(conn)` reads the pair a sign-in request carries: the
  access token as the bearer and the identity token as `privy-id-token`, never in
  a URL or a body. Pass it to `RegentPrivy.Session.verify/2`.
- `RegentPrivy.ContentSecurityPolicy.sign_in()` lists the sources Privy's sign-in
  loads, by directive. Add each list to that directive on the pages that can sign
  someone in, and nowhere else.
- `RegentPrivy.Owners` keeps pages for the Privy accounts the app names. The app
  writes one module with the behaviour's three callbacks (`owners/0`,
  `signed_in/1`, `still_signed_in/1`) and names it twice:

  ```elixir
  plug RegentPrivy.Owners, sign_in: MyAppWeb.Owner, router: MyAppWeb.Router

  live_session :owner, on_mount: [{RegentPrivy.Owners, MyAppWeb.Owner}] do
    ...
  end
  ```

  Anyone else gets the app's not-found page, and a page that is open checks again
  on every navigation, press and message it receives. A press aimed at a
  LiveComponent is not checked, so an owner page handles its presses itself. The
  endpoint's socket must pass `connect_info: [session: ...]`.
- `RegentPrivy.OwnerSession` keeps the sign-in in the app's cookie session, with
  no table, and answers `signed_in/1` and `still_signed_in/1` for the app's
  owners module by `defdelegate`. The sign-in route verifies the pair and calls
  `OwnerSession.put(conn, session)`; the sign-out route calls
  `OwnerSession.sign_out(conn)`, which also disconnects that sign-in's open
  pages. The sign-in ends when the earlier of the two tokens expires.
  `OwnerSession.browser(session)` is what the page hands `startPrivySignIn` as
  `session`.
- The browser half is `assets/privy_sign_in.mjs` (types in `privy_sign_in.d.mts`).
  Add `regent_privy.assets` to the app's `assets.build` and `assets.deploy` aliases;
  it copies both into `assets/vendor/regent_privy/`, which the app leaves out of
  git. The app supplies `react`, `react-dom` and `@privy-io/react-auth`.
  - `readPrivyPair({getIdentityToken, getAccessToken, requireCurrent})` reads the
    identity token, then the access token, and returns both or throws.
  - `privyPairHeaders(pair)` gives the two headers `RegentPrivy.Proof.pair/1` reads.
  - `privyLoginFailure(error)` names a Privy login error, such as `flow_closed`.
  - `startPrivySignIn({appId, sessionPath, csrfToken, session})` starts Privy in a
    hidden element and resolves to `{signIn, signOut}`. Sign-in posts the pair to
    `sessionPath`; sign-out deletes the session there, then logs Privy out, and
    rejects without logging Privy out when the server refuses. While the person
    the server holds stays signed in at Privy, each new Privy token is posted
    again (`onRenewed`), and a page opened after the sign-in ended renews it as a
    sign-in (`onSignedIn`, a reload by default).

`mix check` compiles, checks formatting and runs tests without changing lockfiles.

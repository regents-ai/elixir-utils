# RegentPrivy

Shared Privy identity-token verification for Regent Elixir apps.

`RegentPrivy.verify_token/2` verifies the ES256 signature against the app's
Privy verification key, validates issuer, audience, and time claims, and
returns the verified claims, the Privy user id, and normalized linked wallet
addresses. Apps pass their own Privy configuration per call:

```elixir
RegentPrivy.verify_token(token,
  app_id: "my-privy-app-id",
  verification_key: pem
)
#=> {:ok, %{claims: %{...}, privy_user_id: "did:privy:...",
#=>         wallet_address: "0x...", wallet_addresses: ["0x..."]}}
```

This library holds no configuration or secrets and never logs token contents.

During signing-key rotation, pass `verification_keys: [public_pem_a, public_pem_b]`
instead. The explicit set is bounded to four keys and replaces the singular option;
an empty or malformed set never falls back. Each proof is verified independently
against these configured keys, so a token pair may span a rotation. Signature,
claim and pair-binding checks are unchanged. No key or URL supplied by a token is
trusted, and the library performs no key discovery or network requests.

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

`mix check` compiles, checks formatting and runs tests without changing lockfiles.

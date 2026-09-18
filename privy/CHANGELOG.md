# Changelog

## Unreleased

- `wallet_address` is now the wallet Privy verified most recently (the wallet the
  person signed in with), read from each wallet entry's `lv` time, instead of the
  first wallet listed. A wallet entry without a verification time is not wallet
  evidence.

- Support a bounded, explicitly configured public-key set for signing-key rotation
  in both token and paired-session verification. Preserve single-key callers and
  all existing claim and binding checks; never discover keys from token input.

## 0.1.0

- Initial release: `RegentPrivy.verify_token/2` with ES256 signature
  verification, issuer/audience/time-claim validation, and linked wallet
  address extraction.

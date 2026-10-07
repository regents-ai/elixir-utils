# Changelog

## 0.2.1

- A verification key that is not a readable PEM (for example one written on a
  single line with literal `\n` in place of line breaks) now returns
  `:invalid_verification_key`. Before, it built a signer with no key and every
  token failed as `:token_verification_failed`.

## 0.2.0

- `wallet_address` is now the wallet Privy verified most recently (the wallet the
  person signed in with), read from each wallet entry's `lv` time, instead of the
  first wallet listed. A wallet entry without a verification time is not wallet
  evidence.

## 0.1.0

- Initial release: `RegentPrivy.verify_token/2` with ES256 signature
  verification, issuer/audience/time-claim validation, and linked wallet
  address extraction.

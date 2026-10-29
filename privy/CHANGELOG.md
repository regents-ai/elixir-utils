# Changelog

## Unreleased

- `RegentPrivy.Users`, Privy's server API for an agent that owns its account:
  `by_wallet/2` finds the Privy user a wallet is linked to, and
  `create_with_wallet/2` makes a Privy user for an agent, whose only login is that
  wallet and whose custom metadata names that wallet as `regent_agent`. Both answer
  the Privy id and `agent`, whether an agent opening made that user for the wallet
  asked about. Apps
  pass `:app_id`, `:app_secret` and `:req_options` per call; errors are fixed atoms.
  Adds Req to the package's dependencies.
- jose 1.11.13 in the lock, which fixes the eight jose advisories of 26 Oct
  (EEF-CVE-2026-65625 to -65632, one high).
- `verify_token/2` and `RegentPrivy.Session` now name two wallets apart:
  `embedded_wallet_address`, the wallet Privy made for the person (its
  `wallet_client_type` is `privy`), and `user_wallet_address`, the most recently
  verified wallet the person brought themselves. Each is nil when there is none.
  `wallet_addresses` is unchanged.
- `wallet_address`, the person's main wallet, is now their own wallet when they
  have one and the Regents embedded wallet otherwise. Before, it was whichever
  wallet Privy verified most recently, so Privy making the embedded wallet during
  a sign-in could take the main wallet (and its ENS name) from the person's own.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions. `verify_token/2` drops a catch-all clause
  that Elixir 1.20's type checker proves can never run; every result it returns is
  unchanged. joken 2.7.0.

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

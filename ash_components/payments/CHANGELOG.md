# Changelog

## 0.1.0 (unreleased)

- `RegentPayments.BuyingWallet.buy/2` buys from a sale contract with the
  site's own buying wallet: an approval of exactly the price, mined, then the
  sale call. It answers `{:ok, hashes}`, `{:error, {:approval_failed, hash}}`,
  `{:error, {:call_reverted, sent}}` or `{:error, {:call_unknown, sent}}`;
  `status/2` reads an unknown call's receipt later. Signed sends and receipt
  waits now live in `RegentPayments.Operator`, which `FeeForward` uses too;
  `FeeForward`'s own answers are unchanged. The receipt wait is set with
  `config :regent_payments, RegentPayments.Operator, receipt_every_ms:`.
  Each signed send takes the wallet's next nonce after any transaction still
  waiting, so a send never replaces an earlier one.

- Regent Credits can pay where the money ends with Regents. Every offer's terms
  now say `credits: :accepted | :refused`, frozen into the payload and its digest;
  offers that pay another person's wallet answer `:refused`.
  `Purchase.pay_with_credits/4` holds and charges the price in Credits (one Credit
  per USDC, to the millionth), writes the receipt and settles the intent in one
  transaction under the intent's row lock, then carries the effect out as for
  USDC. An agent's intent is paid only by that agent, person and frozen pairing,
  within the limits the person set; a person's intent is paid only by the person
  whose `privy_user_id` prepared it. Terms accept Credits only when they pay into
  a wallet named in `config :regent_payments, credits_pay_to:`; preparing any
  other `:accepted` terms is refused. Shortfalls and refused spends answer
  `{:credits_refused, intent, words}` and spend nothing.
- Receipts record `paid_with` (`:usdc` or `:credits`). A Credits receipt has no
  payer wallet, chain, asset, facilitator or transaction; its payment response
  names the Credits hold. Migration `20261028090000_receipts_paid_with` adds the
  column filled with `usdc` for existing rows and then drops its default, without
  rewriting a row; it relaxes those four columns and adds a check
  that each receipt is one shape or the other. `FeeForward` answers
  `:paid_with_credits` for a fee paid in Credits.
- `Purchase.on_offer/3` also finds an intent that is paid (`:settlement_pending`
  or `:settled`) once its terms have run out, so a door asked again finishes that
  purchase instead of offering new terms and taking a second payment.
- Depends on `regent_credits` by sibling path; a site's `regent_credits` pin
  replaces it with `override: true`. Its tests migrate the Credits schema into the
  payments test database, since both share one transaction.

- ash_postgres comes from Regent's copy of 2.15.2 (regents-ai/ash_postgres at
  cc886ab3), which carries ash-project/ash_postgres#910: upserts are written to the
  schema the site's repo picks, as on 2.13.0. It clears the two 2.13.0 advisories.
  Ash 3.37.2, ash_sql 0.8.4.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.
- Delegated agent intents freeze private agent, beneficiary and pairing
  attribution. Preparing and first settlement atomically check the original
  pairing. Payment verification runs outside database locks. Already authorized
  payments can finish through `Purchase.complete/3` and the intent-bound
  `CompletionActor`; completion grants no account-owner or ordinary read access.
- `PaymentIntent.payload` is now non-public. Product serializers must return
  explicit customer fields, never the complete payload or private authority.
- Legacy pending intents lack frozen signer evidence and cannot use the new
  completion API. Their existing pending status path remains available and
  never resends settlement. Legacy settled/applied completion requires the
  original payer wallet recorded in the receipt.
- Moved here from the Regents repository (Regents main b258ae02) into
  elixir-utils `ash_components/payments`, owned by the ash-template lane. Module
  names, routes, settings, mix tasks and migrations are unchanged.
- elixir-utils siblings are path dependencies, and the package runs the
  elixir-utils `mix check`.
- Runs on Ash 3.36. Ash postgres stays at 2.13.0.

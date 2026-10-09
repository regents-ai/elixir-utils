# Changelog

## 0.1.0 (unreleased)

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

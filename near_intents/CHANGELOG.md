# Changelog

## 0.1.0 (2026-11-14)

- Initial release: `RegentNearIntents.tokens/0`, `quote/1` and `status/1` for the NEAR to
  USDC on Base route of NEAR Intents 1Click. One call each, no state, no key; every
  failure is `{:error, %{reason, message}}`.

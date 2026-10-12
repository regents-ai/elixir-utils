# Changelog

## 0.1.0 (2026-10-12)

- Initial release: `RegentAnthropic.respond/1` (a Messages API reply with adaptive
  thinking, an optional JSON schema and effort; text and images as input). Every
  result carries its token usage and US dollar cost from `RegentAnthropic.Prices`
  (Claude list prices as of 2026-10-12); unpriced models are refused before
  sending, no redirect is followed, and billed failures still report their cost.

# Changelog

## Unreleased

- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.
- An error Anthropic answers keeps its own message: the reason is now
  `{:anthropic, status, type, message}`, and the error's text ends with it, so a low
  credit balance shows in the logs instead of only "400 (invalid_request_error)".

## 0.1.0 (2026-10-12)

- Initial release: `RegentAnthropic.respond/1` (a Messages API reply with adaptive
  thinking, an optional JSON schema and effort; text and images as input). Every
  result carries its token usage and US dollar cost from `RegentAnthropic.Prices`
  (Claude list prices as of 2026-10-12); unpriced models are refused before
  sending, no redirect is followed, and billed failures still report their cost.

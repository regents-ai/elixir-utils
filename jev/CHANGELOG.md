# Changelog

## Unreleased

- The tests are gone (19 Nov 2026). `mix check` compiles with warnings as errors and
  checks unused locks, formatting and the usage rules. Requests always go through
  Req: the `regent_http` client setting the tests used is gone.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.

## 0.1.0 (2026-10-04)

- Initial release: `RegentJev.decide/3` asks Jev one or more choice questions in one
  OpenRouter Decisions call and returns the answers only when each used an offered key.
  Every result carries its tokens and the US dollar cost OpenRouter reported, billed
  failures still report their cost, and each call emits `[:regent_jev, :decide]`
  telemetry.

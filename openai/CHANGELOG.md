# Changelog

## Unreleased

- The tests are gone (19 Nov 2026). `mix check` compiles with warnings as errors and
  checks unused locks, formatting and the usage rules. Requests always go through
  Req: the `regent_http` client setting the tests used is gone.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.

## 0.1.0 (2026-09-30)

- Initial release: `RegentOpenAI.respond/1` (text and screenshot replies, with an
  optional strict JSON schema), `transcribe/2` and `speak/2` (push-to-talk), and
  `image_data_url/2`. Every result carries its token usage and US dollar cost from
  `RegentOpenAI.Prices` (OpenAI list prices as of 2026-09-30); unpriced models are
  refused before sending, and billed failures still report their cost.

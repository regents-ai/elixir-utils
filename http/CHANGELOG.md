# Changelog

## Unreleased

- `RegentHttp.ClientAddress.key/1`, the address a request's rate limits are keyed
  by: behind Fly's proxy, the one `Fly-Client-IP` the proxy sets, and the direct
  peer anywhere else. `X-Forwarded-For` is never read. The app sets
  `config :regent_http, :behind_fly_proxy, true` in production and `false`
  everywhere else.
- plug_crypto 2.2.1 in the lock, which fixes EEF-CVE-2026-105963 (a secret key base
  shown in a stack trace's arguments).
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.

### Fixed

- `redact/1` also hides Anthropic API keys (`sk-ant-…`), so one can never reach a log through
  `format_error/1`.

## 0.1.0 (2026-06-10)

- Initial release: `RegentHttp.request/1`, `get/2`, `post/2` with shared
  timeout defaults, `[:regent_http, :request]` telemetry, and
  `format_error/1`/`redact/1` secret redaction. Ported from
  `PlatformPhx.ExternalHttpClient`.

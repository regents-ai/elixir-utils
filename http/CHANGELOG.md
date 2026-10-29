# Changelog

## Unreleased

- `RegentHttp.Public.request/3` (and `get/2`) call an address someone else
  supplied, such as an app's published identity or an MCP Events callback:
  HTTPS only, every DNS answer must be public and Mint connects to the checked
  address (the host stays the TLS name), no redirects, a byte limit and a total
  deadline; `answer: :headers` returns on a 2xx status's headers. `uri/1`,
  `valid_url?/1` and `public_ip?/1` are its checks. It emits
  `[:regent_http, :public_request]` without the host, which someone else chose.
  `Regent.MCPEvents.Callback` now uses it instead of its own copy.

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

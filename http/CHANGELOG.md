# Changelog

## Unreleased

- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.
- `RegentHttp.UnexpectedFailure`, moved from the template's
  `AshTemplateWeb.UnexpectedFailure`: `log/2` writes one line for a request answered
  "try again" (the error's module, up to four immediate causes and a SHA-256 of the
  request id), and `attach_jobs/0` writes one line for each Oban job that runs out of
  attempts, from Oban's own `[:oban, :job, :exception]` event. Error messages, request
  bodies and job arguments never reach the log.
- `RegentHttp.ErrorSaving`: a site calls `attach/0` once at start, and a crash that
  ErrorTracker cannot save is one warning line instead of removing ErrorTracker's
  handler until the next restart. ErrorTracker is an optional dependency.

### Fixed

- `redact/1` also hides Anthropic API keys (`sk-ant-…`), so one can never reach a log through
  `format_error/1`.

## 0.1.0 (2026-06-10)

- Initial release: `RegentHttp.request/1`, `get/2`, `post/2` with shared
  timeout defaults, `[:regent_http, :request]` telemetry, and
  `format_error/1`/`redact/1` secret redaction. Ported from
  `PlatformPhx.ExternalHttpClient`.

# Changelog

## 0.1.0 (2026-10-04)

- Initial release: `RegentJev.decide/3` asks Jev one or more choice questions in one
  OpenRouter Decisions call and returns the answers only when each used an offered key.
  Every result carries its tokens and the US dollar cost OpenRouter reported, billed
  failures still report their cost, and each call emits `[:regent_jev, :decide]`
  telemetry.

# Changelog

## 0.2.0

- `RegentAgentAccess.RateLimit`: a plug that counts each request against a
  per-client budget kept by the product's own limiter and answers with the IETF
  `RateLimit-Policy` and `RateLimit` headers. Past the budget it sends 429 with
  `Retry-After` and the JSON error body. `put_headers/3` adds the same headers
  from a controller. The header format comes from Patchbay's `RateLimitHeaders`
  and the budget shape from Regents' `RateLimiter`.
- `RegentAgentAccess.Recovery.json/2` returns `%{error: %{code, message, hint}}`,
  Autolaunch's error document, instead of `%{errors: %{detail, code, hint}}`.
  A product's JSON error pages change shape when it moves its pin.

## 0.1.0

- Initial release: `Accept` negotiation, `Vary` merging, `RegentAgentAccess.Plug`
  for public-document Markdown and error formats, and `RegentAgentAccess.Recovery`
  for Markdown and JSON error bodies. Regents is the first consumer.

# Changelog

## 0.1.0 (2026-09-30)

- Initial release: `RegentOpenAI.respond/1` (text and screenshot replies, with an
  optional strict JSON schema), `transcribe/2` and `speak/2` (push-to-talk), and
  `image_data_url/2`. Every result carries its token usage and US dollar cost from
  `RegentOpenAI.Prices` (OpenAI list prices as of 2026-09-30); unpriced models are
  refused before sending, and billed failures still report their cost.

# RegentOpenAI

OpenAI text replies, transcription and speech for Regent Elixir apps. Every result
says how many tokens it used and what they cost in US dollars, so the site can record
the spend and hold each person to an allowance.

- `respond/1` — a reply from the Responses API: plain text, or an object held to a
  strict JSON schema; text and screenshots as input.
- `transcribe/2` — speech to text for push-to-talk (25 MB limit).
- `speak/2` — text to speech (4,096 character limit).
- `image_data_url/2` — turns a screenshot into an image input.

Nothing is stored at OpenAI (`store: false`), nothing is retried, and inputs and
outputs are never logged. Requests go through `regent_http`.

## Install

```elixir
# mix.exs
{:regent_openai, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "openai"},
{:regent_http, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "http", override: true}
```

`regent_http` is listed by the app itself because `regent_openai` points at it as a
sibling folder.

```elixir
# config/runtime.exs
config :regent_openai, api_key: System.fetch_env!("OPENAI_API_KEY")
```

## Use

```elixir
{:ok, reply} =
  RegentOpenAI.respond(
    model: "gpt-5.6-terra",
    instructions: "Suggest the next step as JSON.",
    input: [{:text, question}, {:image_url, RegentOpenAI.image_data_url(png, "image/png")}],
    schema: {"next_step", next_step_schema},
    reasoning: "low"
  )

reply.json      # the decoded object
reply.cost_usd  # Decimal, US dollars

{:ok, transcript} =
  RegentOpenAI.transcribe(audio,
    model: "gpt-4o-mini-transcribe",
    filename: "clip.webm",
    content_type: "audio/webm"
  )

{:ok, speech} = RegentOpenAI.speak(text, model: "gpt-4o-mini-tts", voice: "marin")
speech.audio         # mp3 bytes
speech.content_type  # "audio/mpeg"
```

Errors are `{:error, %RegentOpenAI.Error{}}`. When OpenAI had already billed the call
(a reply that stopped early, was refused, or broke its schema), the error still carries
`usage` and `cost_usd`; record them like a success.

## Prices and allowances

`RegentOpenAI.Prices` holds OpenAI's list prices per million tokens as of 2026-09-30
(`RegentOpenAI.Prices.as_of/0`). A model not in the table is refused before anything
is sent, so no call goes unpriced. Update the table when OpenAI changes its prices.

The package reports cost; the site enforces its allowance. The pattern for a daily cap
per person:

1. Before the call, sum that person's recorded spend for the day; refuse when it has
   reached the cap.
2. After the call, record `cost_usd` from the result or the billed error.

A call that starts just under the cap can finish slightly over it.

## Test injection

Stub the HTTP client as for `regent_http`:

```elixir
Application.put_env(:regent_http, :client, MyApp.OpenAIStub)
```

## Check

```bash
mix check
```

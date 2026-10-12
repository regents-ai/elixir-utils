# RegentAnthropic

Claude replies for Regent Elixir apps, through Anthropic's Messages API. Every reply
says how many tokens it used and what they cost in US dollars, so the site can record
the spend and hold each person to an allowance.

- `respond/1` — a reply with adaptive thinking: plain text, or an object held to a
  JSON schema; text and images as input.

Nothing is retried, and inputs and outputs are never logged. Requests go through
`regent_http`.

## Install

```elixir
# mix.exs
{:regent_anthropic, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "anthropic"},
{:regent_http, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "http", override: true}
```

`regent_http` is listed by the app itself because `regent_anthropic` points at it as
a sibling folder.

```elixir
# config/runtime.exs
config :regent_anthropic, api_key: System.fetch_env!("ANTHROPIC_API_KEY")
```

## Use

```elixir
{:ok, reply} =
  RegentAnthropic.respond(
    model: "claude-opus-5-5",
    system: "Suggest the next step as JSON.",
    input: [{:text, question}, {:image, "image/png", png}],
    schema: next_step_schema,
    effort: "high",
    max_tokens: 32_000
  )

reply.json      # the decoded object
reply.cost_usd  # Decimal, US dollars
```

Errors are `{:error, %RegentAnthropic.Error{}}`. When Anthropic had already billed the
call (a reply that stopped early, was refused, or broke its schema), the error still
carries `usage` and `cost_usd`; record them like a success.

A reply that may take minutes, such as one with a high `max_tokens` and `effort`,
needs a `receive_timeout` to match.

## Prices and allowances

`RegentAnthropic.Prices` holds Anthropic's list prices per million tokens as of
2026-10-12 (`RegentAnthropic.Prices.as_of/0`). A model not in the table is refused
before anything is sent, so no call goes unpriced. Update the table when Anthropic
changes its prices.

The package reports cost; the site enforces its allowance. The pattern for a daily cap
per person:

1. Before the call, sum that person's recorded spend for the day; refuse when it has
   reached the cap.
2. After the call, record `cost_usd` from the result or the billed error.

A call that starts just under the cap can finish slightly over it.

## Test injection

Stub the HTTP client as for `regent_http`:

```elixir
Application.put_env(:regent_http, :client, MyApp.AnthropicStub)
```

## Check

```bash
mix check
```

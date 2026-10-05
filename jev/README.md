# RegentJev

Typed questions to Jev, TypeSafe's decision model on OpenRouter, for Regent Elixir apps.
Jev answers named questions about a piece of content by picking one of the keys each
question offers, with a confidence. It writes no prose.

- `decide/3` — asks one or more choice questions in a single call and returns the
  answers only when every question came back with one of its own keys.

Every result says how many tokens it used and what OpenRouter charged in US dollars, so
the site can record the spend and hold itself to a budget. A billed answer that did not
use an offered key still carries its cost. Nothing is retried; the site's job queue
retries. Requests go through `regent_http`, and each call emits a
`[:regent_jev, :decide]` telemetry event with its duration, tokens, cost and outcome.

## Install

```elixir
# mix.exs
{:regent_jev, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "jev"},
{:regent_http, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "http", override: true}
```

`regent_http` is listed by the app itself because `regent_jev` points at it as a
sibling folder.

```elixir
# config/runtime.exs
config :regent_jev, api_key: System.fetch_env!("OPENROUTER_API_KEY")
```

While developing, `config :regent_jev, endpoint: "http://127.0.0.1:4198/api/alpha/decisions"`
points the package at a local stand-in, so no paid call is made.

## Use

```elixir
{:ok, decision} =
  RegentJev.decide(
    %{title: note.title, body: note.body},
    %{
      "label" => %{
        instructions: "Which label fits this note best?",
        choices: %{"idea" => "Something to try.", "task" => "Something to do."}
      }
    },
    model: "~typesafe/jev-latest"
  )

decision.answers["label"]  # %{choice: "task", confidence: 0.84}
decision.usage             # %{input_tokens: 476, output_tokens: 70}
decision.cost_usd          # Decimal, US dollars
```

Errors are `{:error, %RegentJev.Error{}}`. When OpenRouter had already billed the call,
the error still carries `usage` and `cost_usd`; record them like a success. A
`{:openrouter, 429, _}` or 5xx answer is worth retrying later.

The `state` leaves the site, so pass only what may be shared with OpenRouter and
TypeSafe. Treat what Jev chose as data: it is one of the keys the site offered, never an
instruction.

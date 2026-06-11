# RegentHttp

Shared Req HTTP client conventions for Regent Elixir apps: default timeouts,
request telemetry, and secret redaction in formatted errors.

## Usage

```elixir
# mix.exs
{:regent_http, path: "../elixir-utils/http"}
```

```elixir
case RegentHttp.get("https://api.example.com/things") do
  {:ok, %{status: 200, body: body}} -> {:ok, body}
  {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
  {:error, reason} -> {:error, RegentHttp.format_error(reason)}
end
```

Defaults applied to every request (overridable per call):

- `receive_timeout: 15_000`
- `connect_options: [timeout: 5_000]`

Every request emits `[:regent_http, :request]` telemetry with `%{duration}`
measurements and `%{method, host, result}` metadata.

`RegentHttp.format_error/1` and `RegentHttp.redact/1` strip bearer tokens,
`sk_live_…`/`sk_test_…`-style keys, and `x-api-key`/`authorization` header
values before anything reaches logs.

## Test injection

```elixir
Application.put_env(:regent_http, :client, MyApp.HttpStub)
```

The stub implements the `RegentHttp` behaviour (`request/1` returning
`{:ok, %Req.Response{}}` or `{:error, term()}`).

## Adoption status

- `platform/` — adopted (replaces `PlatformPhx.ExternalHttpClient`).
- `autolaunch/` — follow-up: `lib/autolaunch/animata_holdings.ex`,
  `lib/autolaunch/erc8004.ex`, `lib/autolaunch/siwa.ex`,
  `lib/autolaunch/cca/rpc.ex` call `Req.*` directly with ad-hoc timeouts.
- `techtree/` — follow-up: `lib/tech_tree/tech.ex`,
  `lib/tech_tree/siwa_client.ex`, `lib/tech_tree/ipfs/*`,
  `lib/tech_tree/node_access/x402_batch_settlement/*`.

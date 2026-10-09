# RegentAgentAccess

Lets a Regent Phoenix product publish its public documents to people and to
agents at the same address, and answer errors in the format the caller asked for.

- `RegentAgentAccess.negotiate/2` picks a format from `Accept` values, honouring
  quality, specificity and an explicit `q=0`.
- `RegentAgentAccess.merge_vary/1` adds `Accept` to `Vary` without dropping the
  encoding, cookie or other dimensions already there.
- `RegentAgentAccess.Plug` serves a public document's Markdown, refuses formats
  it does not have with a 406, and records the error format for `render_errors`.
- `RegentAgentAccess.Recovery` formats Markdown and JSON error bodies from the
  product's own links and hint. The JSON body is `{"error": {"code", "message", "hint"}}`.
- `RegentAgentAccess.RateLimit` counts each request against a per-client budget,
  answers with the IETF `RateLimit-Policy` and `RateLimit` headers, and past the
  budget sends 429 with `Retry-After` and the JSON error body.

The product keeps its list of public documents, its routes, policies, launch
gates and its HTML error page. Only explicitly public, database-free content
belongs in the `:documents` function; everything else reaches the router as before.

## Signed browser transport (unreleased)

`assets/signed_tools.ts` prepares manifest-listed operations and forwards their
exact signed bytes without cookies, redirects or automatic retries. It does not
sign. Supply SIWA's existing signer separately; a runtime without it is blocked.
The host supplies its configured trusted origin, audience, operation manifest and
SIWA's proof-header list. Product endpoints verify through SIWA once, resolve the
current pairing and enforce their own Ash policies.

Run `mix regent_agent_access.assets` in the host before building assets to copy
the helper into `assets/vendor/regent_agent_access/signed_tools.ts`. Keep that
generated file ignored. The reference integration is ash-template. Run the
bounded transport checks with `node --test assets/signed_tools.test.mts` (Node 26).

## Usage

```elixir
# mix.exs
{:regent_agent_access, path: Path.join(shared, "elixir-utils/agent_access")}
```

```elixir
# endpoint.ex, just before the router
plug RegentAgentAccess.Plug,
  documents: &MyAppWeb.PublicDocuments.document/1,
  guide: "/llms.txt"
```

```elixir
# config.exs
render_errors: [
  formats: [html: MyAppWeb.ErrorHTML, json: MyAppWeb.ErrorJSON, md: MyAppWeb.ErrorMD],
  layout: false
]
```

```elixir
defmodule MyAppWeb.ErrorMD do
  def render(template, _assigns) do
    template
    |> Phoenix.Controller.status_message_from_template()
    |> RegentAgentAccess.Recovery.markdown(MyAppWeb.PublicDocuments.recovery_links())
  end
end
```

```elixir
# router.ex: one budget per client address, counted by the product's own limiter
pipeline :rate_limit do
  plug RegentAgentAccess.RateLimit,
    policy: "default",
    limit: 120,
    window: 60,
    admit: &MyApp.RequestRateLimiter.admit/3,
    key: &MyAppWeb.ClientAddress.key/1
end
```

`admit` returns `{:ok, budget}` or `{:error, :rate_limited, budget}` with
`budget = %{limit: _, remaining: _, reset: _, window: _}`. A controller that
counts its own budget adds the same headers with
`RegentAgentAccess.RateLimit.put_headers(conn, policy, budget)`.

Regents is the first consumer: `platform/lib/ash_platform_web/endpoint.ex` and
`platform/lib/ash_platform_web/controllers/error_md.ex` in the Regents monorepo.

## Checks

```bash
mix check
```

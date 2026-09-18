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
  product's own links and hint.

The product keeps its list of public documents, its routes, policies, launch
gates and its HTML error page. Only explicitly public, database-free content
belongs in the `:documents` function; everything else reaches the router as before.

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

Regents is the first consumer: `platform/lib/ash_platform_web/endpoint.ex` and
`platform/lib/ash_platform_web/controllers/error_md.ex` in the Regents monorepo.

## Checks

```bash
mix check
```

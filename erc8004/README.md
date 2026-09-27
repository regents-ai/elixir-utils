# Regent ERC-8004

A distilled Elixir/Phoenix adaptation of [`p4nthera115/erc8004-ui`](https://github.com/p4nthera115/erc8004-ui).
One bounded server read, an explicit snapshot, and ordinary HEEx components. No React,
JavaScript hooks, browser API keys, runtime Ash resources or application database.

## What is retained

| Upstream feature | Small Phoenix surface |
|---|---|
| Name, description, image/identity, owner, last activity | `agent_card` with a deterministic SVG fingerprint and full-identity disclosure |
| Endpoint list/status | `endpoints`; declared destinations, **not** health checks |
| Reputation score | `reputation`; unscaled Decimal average and non-revoked count |
| Feedback list/tags | `feedback_list`; bounded rows with native reviewer/ID disclosures |
| Validation score/list/display | `validations`; status, nullable score and aggregate evidence |
| Recent activity | `activity`; only feedback/validation records in the loaded pages |
| Composed view | `profile`; all of the above with caller-owned pagination slots |
| Loading/error/empty/not found | `state`; accessible status and optional caller-owned retry slot |

`fingerprint` is also usable alone. It is identifier-derived decoration, not a trust seal.
Remote avatars, arbitrary data/IPFS image handling, charts, weighted tag clouds, reply
threads, automatic verification tiers, SDKs and the upstream docs/MCP server are deliberately
not ported. This is not an ERC-8004 registrar, wallet client, health checker or proof verifier.

## Install in a Regent Phoenix product

From a product's `platform/mix.exs`, use the workspace path:

```elixir
{:regent_erc8004, path: "../../elixir-utils/erc8004"}
```

The package uses `regent_ui` from the sibling design-system. Set `REGENT_DEPS_ROOT`
to the directory containing `design-system/`, or set `REGENT_UI_PATH` explicitly
for another checkout layout. A consumer's existing `regent_ui` dependency must resolve
to the same source. This is a workspace/path package, not a published Hex dependency.

Run `mix deps.get`, then `mix regent_erc8004.assets` in the consumer. Keep its existing
`mix regent_ui.assets` and shared CSS import; add this import **after** the Regent UI CSS:

```css
@import "../vendor/regent_erc8004/erc8004.css";
```

That path is relative to the conventional `assets/css/app.css`. Add
`regent_erc8004.assets` to the consumer's asset-build alias when adopting the package.
No consumer alias or product source is changed automatically. The stylesheet is copied
from the package, not independently maintained in the product.

Import `RegentERC8004.Components` in the appropriate web component/LiveView helper.
Preserve the host's `data-brand` / `data-theme`, fonts, navigation and layout. This package
uses shared `Regent.Structure.panel`, Pixel Square headings, Sans body and technical Mono.
It introduces no new palette or shared button/input implementation. Identity cards use
an h2 and their evidence sections use h3; compose them beneath the page's h1.

## Load in the owning action, never in render

Configure the full `eip155:<chain>:0x<40 hex>` registry and a compatible **HTTPS indexer**
from trusted server configuration. Do not take the endpoint or headers from URL parameters.
Use environment-backed runtime config in the product; never put credentials in assigns,
HTML or source. No default chain deployment or free public endpoint is assumed.

```elixir
alias RegentERC8004.Client

{:ok, client} = Client.new(configured_registry, configured_indexer_url,
  headers: configured_headers
)

Client.load(client, agent_id,
  limit: 10,
  feedback_offset: 0,
  validation_offset: 0
)
# {:ok, %RegentERC8004.Snapshot{...}} or {:error, safe_reason}
```

The read uses GraphQL variables, the newest cumulative aggregate, and one extra row
per list for truthful continuation. `limit` is 1–50; offsets are 0–5000. Token IDs are
canonical decimal strings or uint256 integers. No trimming, floats or partial parsing.
Addresses are normalized to lowercase only after syntax validation.

The `protocol(id: chain)` result must report the configured chain and identity-registry
address; the agent must report the requested chain/token. A missing protocol is invalid
data, not permission to bypass the check. This catches inconsistent endpoint configuration,
but a dishonest indexer can still lie. **Indexed data is not cryptographic verification.**

Supported errors: `:invalid_identity`, `:invalid_options`, `:identity_mismatch`,
`:not_found`, `:invalid_data`, `:indexer_error`, `:response_too_large`, `:unavailable`,
and `{:http_status, status}`. `Client.new/3` returns `:invalid_configuration` on bad config.
Errors never contain upstream text, request URLs or headers. The client's Inspect output
also omits its endpoint and headers; do not serialize the configuration struct yourself.

## Ash and LiveView

Ash owns policies, the actor/tenant boundary, provider configuration, cache keys and refresh
cost. The package has **no runtime dependency on Ash**, just as shared Phoenix primitives
should not own domain resources. The optional, actual Ash generic action example is in
[`examples/ash_action.ex`](examples/ash_action.ex). It returns a typed `Snapshot` through
`:struct` with `instance_of`. Its policy explicitly allows public indexed evidence; private
applications must replace that policy and select the configured client under their trusted
scope. Keep Ash's normal `:default_string_length_count` configuration in the application,
register the adapted domain in its `:ash_domains`, and retain the SAT solver required
by its Ash policies (for example `simple_sat` in a standalone consumer).

The example modules are not auto-compiled or registered in a product. To use them, adapt
and place them in the product under its own domain. Their server configuration key is
`:erc8004_example, :client`. Do not expose that configuration to a client browser.

A LiveView calls its actual Ash action in `mount`/`handle_params` or `assign_async`, stores
the resulting snapshot, and renders:

```heex
<.profile snapshot={@snapshot}>
  <:feedback_more>
    <.button :if={@snapshot.feedback.next_offset}
      phx-click="next-feedback"
      phx-value-offset={@snapshot.feedback.next_offset}>
      More feedback
    </.button>
  </:feedback_more>
</.profile>
```

Here `.button` is the product's existing shared Regent button import; the package does
not supply another one. The product must implement the event, validate the submitted
offset, rerun its real action under the current scope and preserve the other list's offset.
There is intentionally no magic event callback or automatic read from a component.

- `snapshot.agent`: `ref`, nullable `name`/`description`/`last_activity`, `owner`, `services`.
- `snapshot.reputation` / `.validation`: `status` (`:ready`, `:empty`, `:unavailable`),
  nullable `count` and nullable Decimal `average` (rounded to two places).
- `snapshot.feedback` / `.validations`: `entries`, `offset`, `has_more`, `next_offset`,
  `limit_reached`. A nil next offset is **not always the end**: check `limit_reached`.
- `snapshot.activity`: timestamped evidence from these loaded pages, not all chain events.

For an existing Ash-backed indexer, project **authorized, loaded fields** into the explicit
wire-shaped DTO documented by `Client`'s query and `examples/data.exs`, then call
`Snapshot.from_graphql(ref, data, options)`. Do not pass an entire Ash record, an unloaded
relationship or a forbidden field as if it were complete public data. No Ecto wrapper,
new resource hierarchy or database synchronization is needed.

Use `<.state status={:loading} />`, `:error`, `:empty` or `:not_found` separately. Only show
`profile` for a successful current result. With `assign_async`, preserve its error/loading
states and reset/cancel stale requests when agent, provider or viewer scope changes. Cache
keys must include the full registry, token, trusted deployment identity and page options.
No credential should be part of a user-visible cache key.

## Evidence and safety semantics

- Reputation is `valueDeltaSum / (feedbackCreated - feedbackRevoked)`, not `valueSum`,
  and not a percentage. It may be signed or above 100. Units across tags may differ.
- Empty aggregate arrays remain **unavailable**, avoiding fabricated zero/no-reviews claims
  during indexer lag. An actual zero-count aggregate is separately `:empty`.
- A pending/expired validation has no displayed completed score. A completed zero remains
  a real `0 / 100`. Response counts do not assert unique validators or exact pending totals.
- No registration, transfer, revocation or response event feed is claimed. A validation's
  creation timestamp is not a separately verified completion time.
- Offset pagination can shift with new/revoked rows and equal timestamps. It is not a
  snapshot-consistent export and has no fabricated total-page count.
- HTTPS links are explicit user navigation with safe rel attributes; other schemes are
  inert text. The server does not fetch metadata URLs, images, service endpoints or replies.
- HEEx escapes text. Full addresses/IDs are reachable with native details/summary on touch
  and keyboard. The components require no hover, animation or JavaScript to reveal evidence.
- The reader disables retries, redirects and decompression. It streams at most 2 MB with
  5-second connection / 10-second receive timeouts. A stalled/slow request still needs the
  product's normal overall async deadline. Text fields are limited to 64 KiB; decimal
  strings to 256 bytes with no exponent/NaN/infinity syntax. Compressed replies are rejected
  as invalid JSON rather than silently decompressed beyond the response cap.

## Run the local component example

```sh
mix deps.get
mix check
mix run --no-start examples/preview.exs
python3 -m http.server 8780 --bind 127.0.0.1 --directory preview
```

Open `http://127.0.0.1:8780/`. It renders the real components in all eight brand/mode
combinations, with native navigation between two example pages and explicit error/loading
states. **All evidence in this preview is synthetic.** No application, database, wallet,
provider credentials or browser JavaScript is needed. `preview/` is ignored generated output.

The runtime implementation is four modules (`Ref`, `Client`, `Snapshot`, `Components`)
plus a CSS-copy Mix task and one domain stylesheet. Bounded behavioral/browser/Ash action
verification lives in workspace artifacts, not a new product-mirroring test suite.

## Attribution

Adapted from upstream revision `666fb276126e3a2a477e94504c2c8dda1951b8b8` (MIT).
The full original copyright notice is retained in `LICENSE` and `NOTICE`. Additional query
fields were checked against [Agent0's schema](https://github.com/agent0lab/subgraph/blob/main/schema.graphql),
not assumed from component names. See `contract.yaml` for the stable boundary.

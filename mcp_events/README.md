# Regent MCP Events

Shared helpers for the [OpenAI MCP Events contract](https://developers.openai.com/plugins/build/mcp-events),
protocol `2026-07-28`. Products own their event definitions, access rules, subscriptions,
durable event records and the Oban job that delivers them. This package owns identity,
signed callback verification and one safe, signed delivery attempt.

```elixir
{:regent_mcp_events, path: "../../elixir-utils/mcp_events"}
```

## Protocol integration

Use the existing authenticated MCP endpoint for `server/discover`, `events/list`,
`events/subscribe` and `events/unsubscribe`. `Regent.MCPEvents.discover/1` returns a
discovery result with event support. Return authorized definitions with `name`,
`delivery: ["webhook"]`, `inputSchema` and `payloadSchema`. Validate filters against
that schema and authorize subscription creation, refresh and removal in the product.

`subscription_id(owner_id, name, arguments, url)` returns `{:ok, id}` or an error.
The owner ID comes from the authenticated principal, including tenant/client scope
where needed. Arguments are JSON objects with string keys, sorted recursively for
identity. Secret rotation does not change identity.

Call `validate_secret/1`, then `verify_callback(id, url, secret)` before activation.
Verification returns `:ok` or `{:error, reason}`; `callback_error(reason)` returns
JSON-RPC error `-32015`. Each verification sends a new random challenge once, accepts
only its constant-time exact echo, and expires within the ten-second network deadline.
Cache successful verification by owner and exact callback URL for a bounded period.
Never reuse another owner's verification. Atomically replace refreshed signing secrets;
retain the old key only during an explicit short rotation window.

Store the identity, owner, filters, URL, secret, expiration and acknowledged cursor
durably and idempotently. Return `id`, `refreshBefore`, `cursor` and `truncated`.
Use a finite default lifetime, respect a shorter `ttlMs`, and return no expiration
only for an explicitly requested and supported unlimited lifetime. Refresh cannot
skip outstanding events. Replay from the acknowledged cursor; report truncation if
history is unavailable. Unsubscribe uses the original name, arguments and callback
URL, is owner-authorized and idempotent, and returns `{}`. ChatGPT does not support
polling/streaming/gap/terminated on this integration; products can retain separate
polling tools for other clients.

## Durable capture and delivery

Capture each occurrence in the **same transaction** as its domain change, before
commit. Use a unique occurrence key so retries cannot create duplicate events. Do
not send HTTP callbacks from that transaction.

Cursors must be serialized and commit-safe per stream. Allocating a sequence before
commit is insufficient: a later transaction can commit first and cause the earlier
event to be skipped. Hold a stream lock through commit, or consume an existing
durable feed with that guarantee.

Delivery is the product's Oban job; this package ships no queue, worker or lease.
Follow the ordered-delivery recipe in the `elixir-stack` skill
(`ash-template/skills/elixir-stack/references/oban.md`): one job per subscription
(an AshOban trigger, or a worker unique on the subscription id), queued in the same
transaction as each new event and swept on a schedule. The job reloads the
subscription, rechecks its owner's access and filters, and calls `deliver/2` outside
any transaction. `deliver/2` answers:

- `:ok`: the receiver acknowledged; advance the cursor with a compare-and-set from
  the value the job read.
- `{:retry, reason}`: return an error so Oban retries the same event with backoff.
  When attempts run out, stop the subscription and keep its cursor.
- `{:stop, reason}`: stop the subscription and keep its cursor for explicit recovery.

Expiration, revocation, unsubscribe and HTTP 410 stop the subscription. HTTP 413 and
invalid envelopes stop it too. Never advance past a failure. A job can run twice, so
the event ID stays the same on every attempt and the receiver can drop a repeat.

## Data and transport

Subscriptions use atom keys: `id`, `owner_id`, `name`, `arguments`, `url`, `secret`,
`active`, `expires_at` (`DateTime` or `nil`). Optional `previous_secret` and
`secret_rotation_expires_at` support signatures from both keys during rotation.
Events use exactly the string keys `eventId`, `name`, `timestamp`, `data`, `cursor`.
The timestamp is the occurrence's ISO 8601 time with a timezone. Validate data against
the product's payload schema before capture. Send summaries and read-tool links for
large records. Source text is untrusted data, never model instructions. Product
write tools must remain idempotent and prevent automation feedback loops.

The complete envelope is limited to 256 KiB. Its exact serialized bytes are signed
and sent using Standard Webhooks HMAC-SHA256. Each attempt gets a fresh signing time.
Keys are `whsec_` base64 values decoding to 24–64 bytes. Never log keys, signatures,
sensitive callback URLs, payloads or owner data.

Every connection resolves DNS again, rejects non-public or mixed public/private
answers, and connects directly to a validated IP. The original hostname remains
the HTTP Host, TLS SNI and certificate verification name. Private, local, reserved,
mapped and transition addresses are blocked. Mint opens a fresh connection without
proxies, redirects, pooling or hidden retries. Requests have a ten-second deadline;
response bodies and headers are bounded. HTTP 2xx acknowledges receipt. Transient
network errors, 408/425/429 and 5xx retry; 410/413 never retry. Other HTTP failures stop.

## Local checks

Run `mix deps.get` and `mix check`. Verify product persistence, restart/replay flows,
real ChatGPT verification and published plugin acceptance in the owning application.

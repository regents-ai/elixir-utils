# Regent MCP Events

Shared helpers for the [OpenAI MCP Events contract](https://developers.openai.com/plugins/build/mcp-events),
protocol `2026-07-28`. Products own their event definitions, access rules, subscriptions
and durable event records. This package owns identity, signed callback verification,
safe delivery and a supervised delivery worker.

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
durable feed with that guarantee. Persist the stable event ID, occurrence timestamp,
payload and cursor. A unique subscription/event queue key prevents duplicate capture.

Implement `Regent.MCPEvents.Adapter` in the product:

```elixir
claim_next(now, lease_ms)
# :empty | {:ok, %{token: lease_token, subscription: subscription,
#                 event: envelope, attempt: persisted_attempt}} | {:error, reason}

authorize_delivery(delivery, now)
# {:ok, current_subscription} | {:stop, reason} | {:error, reason}

finish(delivery, outcome, now)
# :ok | {:error, reason}
```

Claim atomically with a fenced lease, increment the persisted attempt, and select
only the earliest outstanding occurrence per subscription. A scheduled retry or
retained failure blocks later occurrences. Recover abandoned leases after crashes;
their duration must exceed the network deadline plus storage and authorization work.
Reload the subscription and recheck its owner's access and filters before each attempt.
The worker also checks activation, expiration and identity changes.

Finish atomically only while holding the same lease:

- `{:delivered, cursor}` acknowledges the occurrence and advances its cursor.
- `{:retry, reason, next_at}` retains the occurrence and schedules another attempt.
- `{:stop, reason}` retains the failed occurrence and its cursor for explicit recovery.

Expiration, revocation, unsubscribe and HTTP 410 stop the subscription. HTTP 413,
invalid envelopes and exhausted attempts block the occurrence. Never advance past
a failure. A crash after acknowledgement but before the database update may repeat
delivery; the unchanged event ID permits deduplication. Retain failed occurrences
and attempt history under the product's retention policy.

Add `{Regent.MCPEvents.Worker, adapter: MyApp.MCPEvents.Adapter}` after the database
in the product supervisor, or call `Worker.run_once(adapter)` from a durable product
job. Use one mechanism. Defaults are `poll_interval_ms: 1000`, `lease_ms: 60_000`,
`max_attempts: 8`; retry delays grow exponentially up to one hour. Attempts survive
restarts. Attempts are bounded to 1–32, leases to 30 seconds–one hour, and polling to
1–60,000 milliseconds. The optional `:deliver` function is a transient local verification seam;
production uses the default protected transport.

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

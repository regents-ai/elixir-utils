# XMTP Elixir Browser Shim

This package is the thin browser-only boundary for the Elixir SDK.

It keeps only the pieces that must live in the browser:

- worker request and response wiring
- stream delivery over worker messages
- OPFS access for browser storage

It does not reintroduce the old browser SDK surface. Product logic stays in
Elixir.

## What is here

- `WorkerBridge` for request/reply correlation
- `AsyncStream` and `streams` for stream transport helpers
- `Opfs` for browser storage operations
- `workers/opfs` for the actual OPFS worker implementation
- `contracts` and `errors` for the narrow message shapes and failures

## What the main Elixir SDK must wire up

- the public Elixir API that owns product behavior
- the code that decides when to use the browser shim worker
- any persistence or messaging hooks that need the browser boundary

## Hard-cutover rule

This package assumes there is no dual API and no fallback runtime. If the
browser shim is used, it is only because the browser feature itself is
unavoidable.

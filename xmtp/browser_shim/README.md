# XMTP Elixir Browser Shim

This private TypeScript package contains the browser-only pieces used by
`xmtp_elixir_sdk`.

Most Regent apps do not import this package directly. Phoenix and Elixir code
should use the Hex package and the `Xmtp.*` room modules. Use this shim only
when a browser feature is required, such as worker messaging or OPFS-backed
browser storage.

## What Is Here

- `WorkerBridge`: request/reply correlation for browser workers
- `AsyncStream`: stream delivery helpers over worker messages
- `Opfs`: request builders for browser storage operations
- `workers/opfs`: the OPFS worker implementation
- `contracts` and `errors`: the narrow message and error shapes shared by the shim

## What Stays In Elixir

- product room behavior
- room policy
- message persistence
- membership decisions
- wallet approval handling after the browser returns a signature
- any Phoenix UI state

## Development

```bash
npm ci
npm test -- --run
npm run typecheck
```

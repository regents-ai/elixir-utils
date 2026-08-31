# Railgun Elixir

Elixir package for the Kohaku Railgun SDK.

The package keeps the Elixir API small and idiomatic while the supervised native
bridge performs the protocol-heavy Railgun work.

Run checks from this folder:

```bash
mix check
```

Integration tests are reported as skipped unless `INTEGRATION=1`,
`RPC_URL_SEPOLIA`, and Foundry `anvil` are available. The broadcast flow also
requires an Alto executable.

# Railgun Elixir

Elixir package for the Kohaku Railgun SDK.

The package keeps the Elixir API small and idiomatic while the supervised native
bridge performs the protocol-heavy Railgun work.

Run checks from this folder:

```bash
mix test
```

Integration tests require `RPC_URL_SEPOLIA`, Foundry `anvil`, and an Alto
executable.

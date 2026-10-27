# SiwaKeyring

[Changelog](CHANGELOG.md)

`siwa_keyring` is Regent’s encrypted key store for SIWA and wallet-action flows.
The process that holds the store creates wallets in it and signs with them in
place; nothing else reaches the keys.

## Installation

```elixir
def deps do
  [
    {:siwa_keyring,
     path: Path.join(shared, "elixir-utils/siwa/siwa-elixir/apps/siwa_keyring")}
  ]
end
```

## Configure The Wallet Store

```elixir
config :siwa_keyring,
  path: "/data/siwa-keyring.bin",
  password: System.fetch_env!("KEYSTORE_PASSWORD")
```

The wallet file is encrypted with AES-256-GCM.

## Local Service Calls

```elixir
{:ok, wallet} = SiwaKeyring.create_wallet()
{:ok, %{has_wallet: true}} = SiwaKeyring.has_wallet?()
{:ok, address} = SiwaKeyring.get_address()

{:ok, signature} = SiwaKeyring.sign_message("Sign in to Regent")
{:ok, raw_signature} = SiwaKeyring.sign_raw_message("payload-to-bind")
```

Sign a wallet action:

```elixir
action = %{
  "chain_id" => 8453,
  "to" => "0x1111111111111111111111111111111111111111",
  "value" => "0x0",
  "data" => "0x",
  "expected_signer" => address,
  "expires_at" => "2027-05-06T12:00:00Z",
  "risk_copy" => "Signs a prepared Regent action.",
  "idempotency_key" => "platform:action:123"
}

{:ok, signed} = SiwaKeyring.sign_transaction(action)
```

## Security Boundaries

- The key store is used only inside the process that holds it; there are no HTTP routes.
- Use a strong keystore password.
- Do not log private keys, raw signatures or request bodies.

## Development

```bash
mix deps.get
mix test
mix docs
```

# SiwaKeyring

Isolated signer service and Elixir client for Regent SIWA.

Use this package when a Regent process needs a local wallet for SIWA receipts, request signatures, transaction payloads, or authorization payloads.

## Configure The Wallet Store

```elixir
config :siwa_keyring,
  path: "/data/siwa-keyring.json",
  password: System.fetch_env!("KEYSTORE_PASSWORD"),
  secret: System.fetch_env!("KEYRING_PROXY_SECRET")
```

The wallet file is encrypted with AES-256-GCM. The proxy secret signs requests to the keyring routes.

## Local Service Calls

```elixir
{:ok, wallet} = SiwaKeyring.create_wallet()
{:ok, %{has_wallet: true}} = SiwaKeyring.has_wallet?()
{:ok, address} = SiwaKeyring.get_address()

{:ok, signature} = SiwaKeyring.sign_message("Sign in to Regent")
{:ok, raw_signature} = SiwaKeyring.sign_raw_message("payload-to-bind")
```

## HTTP Routes

Mount `SiwaKeyring.Router` behind an internal route:

```elixir
forward "/internal/keyring", SiwaKeyring.Router
```

Available routes:

- `GET /health`
- `POST /create-wallet`
- `POST /has-wallet`
- `POST /get-address`
- `POST /sign-message`
- `POST /sign-raw-message`
- `POST /sign-transaction`
- `POST /sign-authorization`

Every non-health route requires:

- `x-keyring-timestamp`
- `x-keyring-signature`

Build those headers with:

```elixir
body = Jason.encode!(%{"message" => "Sign in to Regent"})

headers =
  SiwaKeyring.Auth.compute_hmac(
    "proxy-secret",
    "POST",
    "/internal/keyring/sign-message",
    body
  )
```

## Remote Client

```elixir
client =
  SiwaKeyring.Client.new(
    base_url: "https://siwa.internal",
    secret: "proxy-secret"
  )

{:ok, %{"address" => address}} = SiwaKeyring.Client.get_address(client)
```

## Development

```bash
mix test
mix format --check-formatted
```

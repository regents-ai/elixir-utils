# SiwaKeyring

[Hex package](https://hex.pm/packages/siwa_keyring)
[Docs](https://hexdocs.pm/siwa_keyring)
[Changelog](CHANGELOG.md)

`siwa_keyring` is Regent’s isolated signing service and Elixir client for SIWA
and wallet-action flows.

Use it when a Regent process needs a wallet address or signature, but should not
receive or store the private key itself.

## Installation

```elixir
def deps do
  [
    {:siwa_keyring, "~> 0.1.1"}
  ]
end
```

When building this package from this repository against the published SIWA Hex
package:

```bash
SIWA_HEX_PUBLISH=1 mix deps.get
```

## Configure The Wallet Store

```elixir
config :siwa_keyring,
  path: "/data/siwa-keyring.bin",
  password: System.fetch_env!("KEYSTORE_PASSWORD"),
  secret: System.fetch_env!("KEYRING_PROXY_SECRET")
```

The wallet file is encrypted with AES-256-GCM. The proxy secret signs internal
requests to the keyring routes.

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

## HTTP Routes

Run `SiwaKeyring.Router` at an internal service root.

Available routes:

- `GET /api/shared/keyring/health`
- `POST /api/shared/keyring/create-wallet`
- `POST /api/shared/keyring/has-wallet`
- `POST /api/shared/keyring/get-address`
- `POST /api/shared/keyring/sign-message`
- `POST /api/shared/keyring/sign-raw-message`
- `POST /api/shared/keyring/sign-transaction`
- `POST /api/shared/keyring/sign-authorization`

Every non-health route requires:

- `x-keyring-timestamp`
- `x-keyring-request-id`
- `x-keyring-signature`

Build those headers with `SiwaKeyring.Auth.compute_hmac/5`:

```elixir
body = Jason.encode!(%{"message" => "Sign in to Regent"})

headers =
  SiwaKeyring.Auth.compute_hmac(
    "proxy-secret",
    "POST",
    "/api/shared/keyring/sign-message",
    body
  )
```

The request id can be used once during the timestamp freshness window.

## Remote Client

```elixir
client =
  SiwaKeyring.Client.new(
    base_url: "https://siwa.internal",
    secret: System.fetch_env!("KEYRING_PROXY_SECRET")
  )

{:ok, %{"address" => address}} =
  SiwaKeyring.Client.get_address(client)

signer = SiwaKeyring.Client.proxy_signer(client)
```

Use the proxy signer anywhere a SIWA signer is expected.

## Security Boundaries

- Keep the keyring service on an internal network.
- Protect every non-health route with HMAC headers.
- Preserve the raw request body for HMAC verification.
- Use a strong keystore password and proxy secret.
- Do not log private keys, raw signatures, request bodies, or auth headers.

## Development

```bash
mix deps.get
mix test
mix docs
```

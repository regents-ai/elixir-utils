# Siwa

[Changelog](CHANGELOG.md)

`siwa` is Regent’s shared Elixir package for wallet sign-in receipts and signed
service requests.

An agent or operator signs in by proving it controls a wallet. The sign-in
service checks that proof and issues a wallet receipt. Every later request
carries the receipt and is signed by the same wallet; this package creates and
verifies those receipts and signs and verifies those requests.

The package verifies identity and request freshness. The consuming product still
decides whether the verified identity may perform the product action.

## Installation

```elixir
def deps do
  [
    {:siwa, path: Path.join(shared, "elixir-utils/siwa/siwa-elixir/apps/siwa")}
  ]
end
```

## Main Jobs

| Job | Function |
| --- | --- |
| Create a receipt | `Siwa.create_receipt/2` |
| Verify a receipt | `Siwa.verify_receipt/2` |
| Sign a protected request | `Siwa.sign_authenticated_request/4` |
| Verify a protected request | `Siwa.verify_authenticated_request/2` |
| Compute body digest headers | `Siwa.content_digest_for_body/1` |
| List the headers a request must carry | `Siwa.required_authenticated_request_headers/1` |
| List the parts a request signature must cover | `Siwa.required_authenticated_request_components/2` |
| Check a wallet signature | `Siwa.WalletSignature.verify/4` |

## Create And Verify A Receipt

The sign-in service issues a receipt once it has checked the wallet's proof:

```elixir
{:ok, receipt} =
  Siwa.create_receipt(%{
    "typ" => "siwa_wallet_receipt",
    "verified" => "wallet_signature",
    "jti" => receipt_id,
    "sub" => "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    "key_id" => "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    "chain_id" => 8453,
    "nonce" => challenge_nonce,
    "aud" => "platform"
  })

{:ok, claims} =
  Siwa.verify_receipt(receipt.token, audience: "platform")
```

The receipt names the wallet (`sub`, with the same address as `key_id`), the
chain it signed in on, the challenge nonce it signed, the audience and a receipt
ID. `create_receipt/2` adds `iat` and `exp`. Always verify the receipt against
the audience that owns the request.

## Sign A Protected Request

```elixir
request = %{
  method: "POST",
  path: "/v1/platform/actions",
  headers: %{"content-type" => "application/json"},
  body: Jason.encode!(%{"action" => "publish"})
}

{:ok, signed_request} =
  Siwa.sign_authenticated_request(request, receipt.token, signer,
    audience: "platform",
    wallet_audiences: ["platform"]
  )
```

The request signature is bound to the method, path, selected headers, timestamp,
receipt, and exact body digest.

## Verify A Protected Request

```elixir
{:ok, verified} =
  Siwa.verify_authenticated_request(signed_request,
    audience: "platform",
    wallet_audiences: ["platform"],
    replay_store: Siwa.RequestAuth.ReplayStore,
    chain_rpcs: %{1 => [rpc_url: ethereum_rpc_url], 8453 => [rpc_url: base_rpc_url]}
  )
```

Verify the signature before consuming replay state, and keep product permission
checks outside this package. `verified.verification_method` says how the wallet
was proven: `:eoa_recovery` (its key, which holds on every chain), or `:erc1271`
or `:erc6492` (a smart wallet's own answer, which holds only on the receipt's
`chain_id`).

An ordinary wallet's signature is checked here with no network call. A smart
wallet (a Safe, a Coinbase Smart Wallet) signs with its own scheme, so any other
signature is checked on the receipt's chain as `chain_rpcs` says for that chain
id: its `rpc_url`, and optionally the `finch` pool and `timeout_ms`. That is
ERC-1271 for a deployed wallet and ERC-6492 for one not deployed yet.
`Siwa.WalletSignature` does both, for sign-in and for every request after it. A
signature the chain could not be asked about answers `{:error, :signature_lookup_failed}` and leaves the replay window
unused. Signatures are at most `Siwa.WalletSignature.max_bytes()` bytes.

## Audiences That Accept Wallet Requests

Only trusted server configuration may opt a product audience into wallet requests,
both when verifying and when signing through this library:

```elixir
Siwa.verify_authenticated_request(signed_request,
  audience: "patchbay",
  wallet_audiences: ["patchbay"],
  replay_store: MyDurableReplayStore
)
```

Never derive `wallet_audiences` from request parameters. Wallet proof grants
neither a human profile nor any product permission; the product decides what the
wallet may do.

A request carries the receipt in `x-siwa-receipt` and the wallet in `x-key-id`,
`x-agent-wallet-address` and `x-agent-chain-id`, with `x-timestamp` and, when it
has a body, `content-digest`. `Siwa.required_authenticated_request_headers/1` and
`Siwa.required_authenticated_request_components/2` describe this shape. Replay
keys separate wallets by chain and audience.

Use a durable replay store in the deployed broker. Its atomic consume must reject
expired entries against the storage clock, even if verification passed before a
pause or delay. Never extend the signed expiration when recording a replay key. The bundled in-memory store is
for local/library use.

## Wallet Actions

`Siwa.WalletAction` validates wallet-ready action envelopes for transaction and
authorization signing. Use it before handing a prepared action to a signer.

```elixir
{:ok, action} = Siwa.WalletAction.validate(action)
:ok = Siwa.WalletAction.require_expected_signer(action, signer_address)
```

## What This Package Does Not Do

- It does not own product sessions.
- It does not decide product permissions.
- It does not store product workflow state.
- It does not expose private keys.
- It does not submit transactions.

## Development

```bash
mix deps.get
mix test
mix docs
```

# RegentNearIntents

NEAR Intents 1Click for Regent Elixir apps: one route, NEAR on NEAR to USDC on Base.

- `tokens/0` — the assets 1Click supports, with their USD prices.
- `quote/1` — what an exact amount of USDC on Base costs in NEAR, and, unless the quote is
  dry, the deposit address the NEAR goes to.
- `status/1` — how the swap behind a deposit address is going.

The 1Click service needs no key. Every call is made once and nothing is kept: the site
keeps its own record of each funding and decides when to read the status again, for
example from an Oban job. The server never holds or moves funds; the person sends NEAR
from their own wallet to the deposit address.

## Install

```elixir
# mix.exs
{:regent_near_intents, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "near_intents"}
```

The package depends only on `req` and `jason`, so it can be pinned on its own commit.

## Use

```elixir
{:ok, quote} =
  RegentNearIntents.quote(%{
    usdc_amount: 5_000_000,                                    # 5 USDC, in base units
    recipient: "0x1111111111111111111111111111111111111111",   # an address the site has verified
    refund_to: "alice.near",
    dry: false
  })

quote.amount_in_formatted   #=> "1.651313840569386417635746" (NEAR to send)
quote.deposit_address       #=> where to send it, before quote.deadline

{:ok, %{state: state, origin_tx: origin_tx, destination_tx: destination_tx}} =
  RegentNearIntents.status(quote.deposit_address)
```

A dry quote (`dry: true`) only prices the swap: its `deposit_address` is `nil` and its
`deadline` is the one the request asked for, one hour after the call.

`state` is one of:

| 1Click status | `state` |
| --- | --- |
| `PENDING_DEPOSIT`, `KNOWN_DEPOSIT_TX`, `INCOMPLETE_DEPOSIT` | `:pending_deposit` |
| `PROCESSING` | `:processing` |
| `SUCCESS` | `:success` |
| `REFUNDED` | `:refunded` |
| `FAILED` | `:failed` |

A status 1Click has not documented is an error, never a guess.

Every failure is `{:error, %{reason: reason, message: text}}`, with `reason` one of
`:invalid_request` (the call broke the contract above and nothing was sent),
`:not_found` (1Click does not know the deposit address), `:http_error`, `:transport` or
`:unexpected_response`.

## The route

Fixed in the module, with no options:

| Field | Value |
| --- | --- |
| `originAsset` | `nep141:wrap.near` (NEAR) |
| `destinationAsset` | `nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near` (USDC on Base) |
| `swapType` | `EXACT_OUTPUT` (`amount` is the USDC to deliver) |
| `depositType`, `refundType` | `ORIGIN_CHAIN` |
| `recipientType` | `DESTINATION_CHAIN` |
| `slippageTolerance` | `100` (1%) |
| `deadline` | one hour after the call |

## Not in this version

The response signature 1Click puts on each quote is kept in `raw` but not checked. There
is no deposit memo, no other route, and no call that tells 1Click a deposit was sent.

## Tests

Tests stub 1Click with `Req.Test`:

```elixir
Application.put_env(:regent_near_intents, :req_options, plug: {Req.Test, MyTest})
```

`test/fixtures/tokens.json` and `test/fixtures/quote_dry.json` are real answers captured
on 14 November 2026. `test/fixtures/status_success.json` is written from 1Click's
published answer shape, not captured.

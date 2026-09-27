# RegentChain

The server side of Regent's wallet buttons. The server builds every step a button
sends and pushes it to the page before the press, so the press goes straight to the
wallet; afterwards the server checks what the sent transaction did. The
`onchain-buttons` skill in ash-template describes the page half.

| Module | Job |
| --- | --- |
| `RegentChain.Address` | Decode one address, verifying an EIP-55 checksum and refusing the zero address; lowercase for steps, checksummed for display. |
| `RegentChain.Call` | Calldata from an exact function signature, with tuples, arrays and `bytes`. |
| `RegentChain.Review` | The `onchain-steps:review` payload: component, signer, chain and steps. |
| `RegentChain.Outcome` | Pending, confirmed or reverted for a sent step, after checking its sender, target, calldata and value. |
| `RegentChain.Event` | `topic0`, and the one log of an event in a receipt, as words. |

JSON-RPC reads stay in each app: `Outcome` takes the app's client module, whose
`transaction/1` and `receipt/1` return `{:ok, map | nil}` read at `latest`.

## Usage

```elixir
{:regent_chain, path: "../elixir-utils/chain"}
```

Build the steps as soon as the figures are known, and push them again when they change:

```elixir
alias RegentChain.{Call, Review}

review =
  Review.new(socket.assigns.id, wallet, %{chain_id: 8453, name: "Base", rpc_url: rpc_url}, [
    Review.step("approve", usdc, Call.encode("approve(address,uint256)", [pool, amount])),
    Review.step("stake", pool, Call.encode("stake(uint256)", [amount]))
  ])

socket |> assign(:review, review) |> push_event("onchain-steps:review", review)
```

When the page reports a hash, check it against the step every two seconds:

```elixir
RegentChain.Outcome.of(MyApp.Chain.Client, hash, review.signer, step)
#=> {:ok, :pending} | {:ok, :confirmed} | {:ok, :reverted} | {:error, :not_this_step}
```

Read an event from the receipt:

```elixir
{:ok, {[from, to], [amount]}} =
  RegentChain.Event.one(receipt["logs"], "Transfer(address,address,uint256)", token, 2, 1)

{:ok, recipient} = RegentChain.Event.address(to)
```

## Development

```sh
mix deps.get
mix check
```

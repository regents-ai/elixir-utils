# RegentChain

The server side of Regent's wallet buttons. The server builds every step a button
sends and pushes it to the page before the press, so the press goes straight to the
wallet; afterwards the server checks what the sent transaction did. The
`onchain-buttons` skill in ash-template describes the page half.

| Module | Job |
| --- | --- |
| `RegentChain.Address` | Decode one address, verifying an EIP-55 checksum and refusing the zero address; lowercase for steps, checksummed for display. |
| `RegentChain.Call` | Calldata from an exact function signature, with tuples, arrays and `bytes`. |
| `RegentChain.Review` | The review pushed to the page: component, signer, chain, steps (transactions or EIP-712 signatures) and the on-screen inputs, named by an `id` derived from all of them. |
| `RegentChain.Presses` | The reviews a page pushed and each step its wallet sent, checked against the review it was sent from. |
| `RegentChain.Outcome` | Pending, confirmed or reverted for a sent step, after checking its chain, sender, target, calldata and value. |
| `RegentChain.Event` | `topic0`, and the one log of an event in a receipt, as words. |

JSON-RPC reads stay in each app: `Outcome` takes the app's client module, whose
`transaction/2` and `receipt/2` take the review's chain and a hash and return
`{:ok, map | nil}` read at `latest`.

## Usage

```elixir
{:regent_chain,
 git: "https://github.com/regents-ai/elixir-utils.git", ref: @elixir_utils_ref, sparse: "chain"}
```

Build the review as soon as the figures are known, remember it, and push it again
when it changes:

```elixir
alias RegentChain.{Call, Presses, Review}

review =
  Review.new(
    socket.assigns.id,
    signer,
    %{chain_id: 8453, name: "Base", rpc_url: rpc_url},
    [
      Review.step("approve", usdc, Call.encode("approve(address,uint256)", [pool, amount])),
      Review.step("stake", pool, Call.encode("stake(uint256)", [amount]))
    ],
    %{"amount" => "12.5"}
  )

socket
|> assign(:presses, Presses.remember(socket.assigns.presses, review))
|> push_event("onchain-steps:review", %{component_id: socket.assigns.id, review: review})
```

The page reports `%{"review_id", "step", "transaction_hash"}`. Check the step
against that review every two seconds while it is being read:

```elixir
{:ok, entry, presses} = Presses.sent(presses, params)

RegentChain.Outcome.of(MyApp.Chain.Client, entry.review, entry.step, entry.hash)
#=> {:ok, :pending} | {:ok, :confirmed} | {:ok, :reverted} | {:error, :not_this_step}
```

A signature step reports `%{"review_id", "step", "signature"}`; `Presses.signed/2`
returns the server's own typed data with it.

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

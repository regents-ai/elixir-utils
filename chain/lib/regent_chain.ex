defmodule RegentChain do
  @moduledoc """
  Server-built wallet steps for Regent apps.

  The server builds every step a wallet button sends and pushes it to the page before
  the press, so the press goes straight to the wallet. Then it checks what the sent
  transaction did.

  - `RegentChain.Address`: one checked address.
  - `RegentChain.Call`: calldata from a function signature.
  - `RegentChain.Review`: the steps pushed to the page.
  - `RegentChain.Outcome`: whether a sent step is pending, confirmed or reverted.
  - `RegentChain.Event`: one event read back out of a receipt.

  The chain client (JSON-RPC reads at `latest`) stays in each app.
  """
end

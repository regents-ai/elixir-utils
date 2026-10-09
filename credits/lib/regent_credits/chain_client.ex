defmodule RegentCredits.ChainClient do
  @moduledoc """
  The site's JSON-RPC reads, all at the `latest` block. `transaction/2` and
  `receipt/2` are what `RegentChain.Outcome` takes; Ethereum purchases also
  need the chain's newest block number. `logs/2` is `eth_getLogs` with the
  filter as given, which `RegentCredits.Deposits` reads Base deposits with.
  """

  @callback transaction(RegentChain.Review.chain(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}
  @callback receipt(RegentChain.Review.chain(), String.t()) ::
              {:ok, map() | nil} | {:error, term()}
  @callback block_number(RegentChain.Review.chain()) ::
              {:ok, non_neg_integer()} | {:error, term()}
  @callback logs(RegentChain.Review.chain(), map()) :: {:ok, [map()]} | {:error, term()}
end

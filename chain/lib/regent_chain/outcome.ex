defmodule RegentChain.Outcome do
  @moduledoc """
  What a sent step did, read at the chain's latest block.

  `client` is the site's chain client: a module whose `transaction/1` and
  `receipt/1` return `{:ok, map | nil}` for a hash, read at `latest` (see the
  `chain-events` skill). Never count confirmations and never wait for `safe` or
  `finalized`.
  """

  alias RegentChain.Address

  @type t :: :pending | :confirmed | :reverted

  @doc """
  `:pending` until the receipt exists, then `:confirmed` or `:reverted`. A hash
  whose sender, target, calldata or value is not the step's is
  `{:error, :not_this_step}`: it is no answer about the step.
  """
  @spec of(module(), String.t(), String.t(), RegentChain.Review.step()) ::
          {:ok, t()} | {:error, term()}
  def of(client, hash, signer, step) do
    with {:ok, tx} when is_map(tx) <- client.transaction(hash),
         true <- same_step?(tx, signer, step) || {:error, :not_this_step},
         {:ok, receipt} <- client.receipt(hash) do
      {:ok, status(receipt)}
    else
      {:ok, nil} -> {:ok, :pending}
      error -> error
    end
  end

  defp same_step?(tx, signer, %{to: to, data: data, value: value}) do
    Address.equal?(tx["from"], signer) and Address.equal?(tx["to"], to) and
      String.downcase(tx["input"] || "") == data and quantity(tx["value"]) == quantity(value)
  end

  defp quantity("0x" <> hex) when hex != "", do: String.to_integer(hex, 16)
  defp quantity(_value), do: :unreadable

  defp status(nil), do: :pending
  defp status(%{"status" => "0x1"}), do: :confirmed
  defp status(%{"status" => "0x0"}), do: :reverted
end

defmodule RegentChain.Outcome do
  @moduledoc """
  What a sent step did, read at the latest block of the chain its review names.

  `client` is the site's chain client: a module whose `transaction/2` and
  `receipt/2` take the review's chain and a hash and return `{:ok, map | nil}`,
  read at `latest` (see the `chain-events` skill). Never count confirmations and
  never wait for `safe` or `finalized`.
  """

  alias RegentChain.Address

  @type t :: :pending | :confirmed | :reverted

  @doc """
  `:pending` until the receipt exists, then `:confirmed` or `:reverted`. A hash
  whose chain, sender, target, calldata or value is not the step's, as the review
  built it, is `{:error, :not_this_step}`: it is no answer about the step.
  """
  @spec of(module(), RegentChain.Review.t(), RegentChain.Review.transaction(), String.t()) ::
          {:ok, t()} | {:error, term()}
  def of(client, %{chain: chain, signer: signer}, %{kind: "transaction"} = step, hash) do
    with {:ok, tx} when is_map(tx) <- client.transaction(chain, hash),
         true <- same_step?(tx, chain, signer, step) || {:error, :not_this_step},
         {:ok, receipt} <- client.receipt(chain, hash) do
      {:ok, status(receipt)}
    else
      {:ok, nil} -> {:ok, :pending}
      error -> error
    end
  end

  @doc """
  Whether the chain holds the step's transaction yet, without reading its
  receipt: `{:ok, :unknown}` before it does, then `{:ok, :sent}`. A hash whose
  transaction is not the step's is `{:error, :not_this_step}`.
  """
  @spec sent(module(), RegentChain.Review.t(), RegentChain.Review.transaction(), String.t()) ::
          {:ok, :unknown | :sent} | {:error, term()}
  def sent(client, %{chain: chain, signer: signer}, %{kind: "transaction"} = step, hash) do
    case client.transaction(chain, hash) do
      {:ok, nil} ->
        {:ok, :unknown}

      {:ok, tx} when is_map(tx) ->
        if same_step?(tx, chain, signer, step), do: {:ok, :sent}, else: {:error, :not_this_step}

      error ->
        error
    end
  end

  defp same_step?(tx, %{chain_id: chain_id}, signer, %{to: to, data: data, value: value}) do
    quantity(tx["chainId"]) == chain_id and Address.equal?(tx["from"], signer) and
      Address.equal?(tx["to"], to) and String.downcase(tx["input"] || "") == data and
      quantity(tx["value"]) == quantity(value)
  end

  defp quantity("0x" <> hex) when hex != "", do: String.to_integer(hex, 16)
  defp quantity(_value), do: :unreadable

  defp status(nil), do: :pending
  defp status(%{"status" => "0x1"}), do: :confirmed
  defp status(%{"status" => "0x0"}), do: :reverted
end

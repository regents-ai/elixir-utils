defmodule RegentPoints.Nfts do
  @moduledoc "Base ERC-721 holdings from the three collections on Regents' redemption page."
  @chain %{chain_id: 8453}
  # regents/platform/contracts/base-mainnet.json, animata_redeemer.onchain_constants.
  @collections [
    "0x78402119ec6349a0d41f12b54938de7bf783c923",
    "0x903c4c1e8b8532fbd3575482d942d493eb9266e2",
    "0x2208aadbdecd47d3b4430b5b75a175f6d885d487"
  ]
  def collections, do: @collections
  def rpc(method, args), do: RegentPoints.chain_client().rpc(@chain, method, args)
  defp number("0x" <> n), do: String.to_integer(n, 16)

  @doc "Holdings across the collections for `wallets` at the latest Base block."
  def latest(wallets) do
    case rpc("eth_getBlockByNumber", ["latest", false]) do
      {:ok, %{"number" => height, "hash" => hash}} ->
        holdings(wallets, %{number: number(height), hash: hash})

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :block_unavailable}
    end
  end

  defp holdings(wallets, block) do
    calls = for wallet <- Enum.uniq(wallets), collection <- @collections, do: {wallet, collection}

    Enum.reduce_while(calls, {:ok, 0}, fn {wallet, collection}, {:ok, count} ->
      case balance(wallet, collection, block) do
        {:ok, balance} -> {:cont, {:ok, count + balance}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, count} -> {:ok, %{count: count, block: block.number, hash: block.hash}}
      error -> error
    end
  end

  defp balance("0x" <> wallet, collection, block) do
    data = "0x70a08231" <> String.pad_leading(wallet, 64, "0")

    case rpc("eth_call", [
           %{to: collection, data: data},
           %{blockHash: block.hash, requireCanonical: true}
         ]) do
      {:ok, "0x" <> raw} when byte_size(raw) == 64 -> parse_balance(raw)
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_nft_balance}
    end
  end

  defp parse_balance(raw) do
    case Integer.parse(raw, 16) do
      {balance, ""} -> {:ok, balance}
      _ -> {:error, :invalid_nft_balance}
    end
  end
end

defmodule RegentPoints.Nfts do
  @moduledoc "Base ERC-721 holdings from the three collections on Regents' redemption page."
  alias RegentPoints.{Rules, Store}
  @chain %{chain_id: 8453}
  # regents/platform/contracts/base-mainnet.json, animata_redeemer.onchain_constants.
  @collections [
    "0x78402119ec6349a0d41f12b54938de7bf783c923",
    "0x903c4c1e8b8532fbd3575482d942d493eb9266e2",
    "0x2208aadbdecd47d3b4430b5b75a175f6d885d487"
  ]
  @transfer "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  def collections, do: @collections
  def tracking?, do: Keyword.get(Rules.config(), :nft_tracking_enabled, false)
  def rpc(method, args), do: RegentPoints.chain_client().rpc(@chain, method, args)
  def hex(n), do: "0x" <> Integer.to_string(n, 16)
  def number("0x" <> n), do: String.to_integer(n, 16)

  def block(n) do
    tag = if n == :latest, do: "latest", else: hex(n)

    case rpc("eth_getBlockByNumber", [tag, false]) do
      {:ok, %{"number" => height, "hash" => hash, "timestamp" => time}} ->
        {:ok, %{number: number(height), hash: hash, timestamp: number(time)}}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :block_unavailable}
    end
  end

  def latest(wallets) do
    with {:ok, head} <- block(:latest), do: holdings(wallets, head)
  end

  def at_time([], _time), do: {:ok, %{count: 0, block: nil, hash: nil}}

  def at_time(wallets, at) do
    time = DateTime.to_unix(at)

    with {:ok, head} <- block(:latest),
         {:ok, head} <- at_or_before(time, 0, head.number, head) do
      holdings(wallets, head)
    end
  end

  # Find the last block at or before the trusted action timestamp. This is bounded
  # by log2(chain height); it is not a scheduler or a polling loop.
  defp at_or_before(time, _low, _high, %{timestamp: t} = head) when t <= time, do: {:ok, head}

  defp at_or_before(_time, low, high, _head) when low > high,
    do: {:error, :no_block_at_action_time}

  defp at_or_before(time, low, high, _head) do
    middle = div(low + high, 2)

    with {:ok, block} <- block(middle) do
      if block.timestamp > time do
        at_or_before(time, low, middle - 1, block)
      else
        last_before(time, middle, high, block)
      end
    end
  end

  defp last_before(_time, low, high, best) when low >= high, do: {:ok, best}

  defp last_before(time, low, high, best) do
    middle = div(low + high + 1, 2)

    with {:ok, block} <- block(middle) do
      if block.timestamp <= time,
        do: last_before(time, middle, high, block),
        else: last_before(time, low, middle - 1, best)
    end
  end

  def holdings(wallets, block) do
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

  def transfer_wallets(first, last) do
    filter = %{
      address: @collections,
      topics: [@transfer],
      fromBlock: hex(first),
      toBlock: hex(last)
    }

    case rpc("eth_getLogs", [filter]) do
      {:ok, logs} when is_list(logs) -> collect_wallets(logs)
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_transfer_response}
    end
  end

  defp collect_wallets(logs) do
    Enum.reduce_while(logs, {:ok, []}, fn log, {:ok, wallets} ->
      case transfer_addresses(log) do
        {:ok, addresses} -> {:cont, {:ok, addresses ++ wallets}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, wallets} -> {:ok, Enum.uniq(wallets) -- ["0x" <> String.duplicate("0", 40)]}
      error -> error
    end
  end

  defp transfer_addresses(%{
         "address" => address,
         "topics" => [@transfer, from, to, _token],
         "removed" => false
       })
       when address in @collections and byte_size(from) == 66 and byte_size(to) == 66 do
    {:ok, Enum.map([from, to], &String.downcase("0x" <> String.slice(&1, -40, 40)))}
  end

  defp transfer_addresses(_), do: {:error, :invalid_transfer_log}

  def wallet_digest(wallets), do: Store.digest(Enum.sort(Enum.uniq(wallets)))
end

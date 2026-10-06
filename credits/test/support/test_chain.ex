defmodule RegentCredits.TestChain do
  @moduledoc """
  A stand-in for the site's chain client. Tests say what the chain holds for
  each transaction hash (and the newest Ethereum block); every reader, in
  any process, sees it.
  """
  @behaviour RegentCredits.ChainClient

  alias RegentCredits.Chains

  def start, do: :ets.new(__MODULE__, [:named_table, :public, read_concurrency: true])

  @doc "A fresh transaction hash."
  def hash, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

  @doc "The chain holds `tx` and, once mined, `receipt` under `hash`."
  def put(hash, tx, receipt), do: :ets.insert(__MODULE__, {hash, tx, receipt})

  def head(number), do: :ets.insert(__MODULE__, {:head, number})

  @doc "The transaction `wallet` sent for a purchase's buy step."
  def buy(chain, wallet, amount, number) do
    step = Chains.buy_step(chain, amount, number)

    %{
      "chainId" => "0x" <> Integer.to_string(Chains.chain(chain).chain_id, 16),
      "from" => wallet,
      "to" => step.to,
      "input" => step.data,
      "value" => step.value
    }
  end

  def mined(status, block \\ 1, block_hash \\ hash(), logs \\ []) do
    %{
      "status" => status,
      "blockNumber" => "0x" <> Integer.to_string(block, 16),
      "blockHash" => block_hash,
      "logs" => logs
    }
  end

  @doc "A USDC Transfer log."
  def transfer_log(chain, from, to, micro) do
    %{
      "address" => Chains.usdc(chain),
      "topics" => [
        RegentChain.Event.topic0("Transfer(address,address,uint256)"),
        word(from),
        word(to)
      ],
      "data" => "0x" <> String.pad_leading(Integer.to_string(micro, 16), 64, "0")
    }
  end

  defp word("0x" <> address), do: "0x" <> String.pad_leading(address, 64, "0")

  @impl true
  def transaction(_chain, hash), do: {:ok, read(hash, 1)}

  @impl true
  def receipt(_chain, hash), do: {:ok, read(hash, 2)}

  @impl true
  def block_number(_chain) do
    [{:head, number}] = :ets.lookup(__MODULE__, :head)
    {:ok, number}
  end

  defp read(hash, field) do
    case :ets.lookup(__MODULE__, hash) do
      [row] -> elem(row, field)
      [] -> nil
    end
  end
end

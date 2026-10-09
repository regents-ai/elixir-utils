defmodule RegentCredits.TestChain do
  @moduledoc """
  A stand-in for the site's chain client. Tests say what the chain holds for
  each transaction hash, each chain's newest block and the deposits Base
  logged; every reader, in any process, sees it.
  """
  @behaviour RegentCredits.ChainClient

  alias RegentCredits.Chains

  def start, do: :ets.new(__MODULE__, [:named_table, :public, read_concurrency: true])

  @doc "A fresh transaction hash."
  def hash, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

  @doc "The chain holds `tx` and, once mined, `receipt` under `hash`."
  def put(hash, tx, receipt), do: :ets.insert(__MODULE__, {hash, tx, receipt})

  def head(chain, number), do: :ets.insert(__MODULE__, {{:head, chain}, number})

  @doc "The logs Base holds, replacing any before."
  def logs(logs), do: :ets.insert(__MODULE__, {:logs, logs})

  @doc "A Credits deposit of `micro` USDC from `wallet` in `block`, as REGENT staking logs it."
  def deposit_log(wallet, micro, block, options \\ []) do
    {:ok, number} = Ecto.UUID.dump(Keyword.get(options, :number, Ecto.UUID.generate()))
    "0x" <> tag = Keyword.get(options, :tag, Chains.source_tag())

    %{
      "address" => Chains.staking(),
      "blockNumber" => "0x" <> Integer.to_string(block, 16),
      "transactionHash" => Keyword.get(options, :tx_hash, hash()),
      "removed" => false,
      "topics" => [
        RegentChain.Event.topic0(
          "USDCRevenueDeposited(uint256,uint256,uint256,uint8,address,bytes32,bytes32)"
        ),
        "0x" <> String.duplicate("0", 64),
        word(wallet),
        "0x" <> Base.encode16(<<0::128, number::binary>>, case: :lower)
      ],
      "data" => "0x" <> number_word(micro) <> number_word(0) <> number_word(micro) <> tag
    }
  end

  defp number_word(value), do: String.pad_leading(Integer.to_string(value, 16), 64, "0")

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
  def block_number(%{chain_id: chain_id}) do
    name = if chain_id == Chains.chain(:base).chain_id, do: :base, else: :ethereum
    [{_key, number}] = :ets.lookup(__MODULE__, {:head, name})
    {:ok, number}
  end

  @impl true
  def logs(_chain, %{"address" => address, "topics" => topics} = filter) do
    {:ok, from} = RegentChain.Abi.quantity(filter["fromBlock"])
    {:ok, to} = RegentChain.Abi.quantity(filter["toBlock"])

    logs =
      case :ets.lookup(__MODULE__, :logs) do
        [{:logs, logs}] -> logs
        [] -> []
      end

    {:ok,
     Enum.filter(logs, fn log ->
       {:ok, block} = RegentChain.Abi.quantity(log["blockNumber"])

       block in from..to and RegentChain.Address.equal?(log["address"], address) and
         Enum.take(log["topics"], length(topics)) == topics
     end)}
  end

  defp read(hash, field) do
    case :ets.lookup(__MODULE__, hash) do
      [row] -> elem(row, field)
      [] -> nil
    end
  end
end

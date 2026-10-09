defmodule RegentCredits.Deposits do
  @moduledoc """
  Reads every Credits deposit on Base from the chain and credits each one
  once, whoever sent it and whether or not a page reported it.

  A Credits deposit is a `USDCRevenueDeposited` event of REGENT staking whose
  source tag is `regent.credits`. Each run reads from the chain's
  `RegentCredits.DepositCursor` up to 300 blocks (ten minutes) behind the
  newest one, 500 blocks at a time, and moves the cursor on after each
  stretch is credited. The ten minutes keep it clear of a log search that
  lags the newest block, which would answer an unsearched stretch with no
  logs; the page's own report credits sooner. A stretch the node refuses is
  read again in halves, down to one block.

  Two sites reading the same chain at once credit each deposit once between
  them; the one that finds the cursor already past its stretch stops there.

  A transaction is credited at most once, together with any report of it
  (`RegentCredits.Purchases.credit_deposit/1`). Reads happen outside any
  database transaction; each deposit is credited in a transaction of its own.
  """

  require Ash.Query

  alias RegentChain.{Abi, Address, Event}
  alias RegentCredits.{Chains, DepositCursor, Purchase}

  @event "USDCRevenueDeposited(uint256,uint256,uint256,uint8,address,bytes32,bytes32)"
  @direct_deposit "0x" <> String.duplicate("0", 64)
  @span 500
  @behind 300

  @doc "Credits the chain's deposits since its cursor, up to 300 blocks behind the newest."
  @spec read(:base) :: :ok | {:error, term()}
  def read(name) do
    # Internal: read by the Oban read of the chain.
    cursor = Ash.get!(DepositCursor, name, authorize?: false)
    chain = Chains.chain(name)

    with {:ok, head} <- Chains.client().block_number(chain) do
      read_on(cursor, chain, head - @behind, @span)
    end
  end

  defp read_on(%{next_block: from}, _chain, last, _span) when from > last, do: :ok

  defp read_on(%{next_block: from} = cursor, chain, last, span) do
    to = min(last, from + span - 1)

    case Chains.client().logs(chain, filter(from, to)) do
      {:ok, logs} ->
        with {:ok, deposits} <- deposits(logs, cursor.chain),
             :ok <- credit_all(deposits),
             {:ok, cursor} <- advance(cursor, from, to + 1) do
          read_on(cursor, chain, last, span)
        end

      {:error, _reason} when span > 1 ->
        read_on(cursor, chain, last, div(span, 2))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp filter(from, to) do
    %{
      "address" => Chains.staking(),
      "topics" => [Event.topic0(@event), @direct_deposit],
      "fromBlock" => quantity(from),
      "toBlock" => quantity(to)
    }
  end

  defp quantity(number), do: "0x" <> String.downcase(Integer.to_string(number, 16))

  # One deposit per transaction: the Credits deposits it holds, added up and
  # credited to the wallet behind the first of them.
  defp deposits(logs, chain) do
    logs
    |> Enum.reject(&match?(%{"removed" => true}, &1))
    |> Enum.reduce_while({:ok, []}, fn log, {:ok, found} ->
      case deposit(log) do
        {:ok, nil} -> {:cont, {:ok, found}}
        {:ok, deposit} -> {:cont, {:ok, [deposit | found]}}
        :error -> {:halt, {:error, {:unreadable_deposit, log}}}
      end
    end)
    |> case do
      {:ok, found} -> {:ok, found |> Enum.reverse() |> by_transaction(chain)}
      error -> error
    end
  end

  defp deposit(%{"address" => address, "transactionHash" => hash} = log) do
    with true <- Address.equal?(address, Chains.staking()),
         {:ok, hash} <- Abi.hash(hash),
         {:ok, {[0, depositor, ref], [micro, _stakers, _treasury, tag_word]}} <-
           Event.one([log], @event, Chains.staking(), 3, 4),
         {:ok, depositor} <- Event.address(depositor) do
      if tag_word == tag_word(),
        do: {:ok, %{tx_hash: hash, wallet: depositor, micro: micro, number: number(ref)}},
        else: {:ok, nil}
    else
      _unreadable -> :error
    end
  end

  defp deposit(_log), do: :error

  defp by_transaction(deposits, chain) do
    deposits
    |> Enum.group_by(& &1.tx_hash)
    |> Enum.map(fn {_hash, [first | _rest] = same} ->
      micro = same |> Enum.map(& &1.micro) |> Enum.sum()
      first |> Map.delete(:micro) |> Map.merge(%{chain: chain, amount: amount(micro)})
    end)
  end

  defp credit_all(deposits) do
    Enum.reduce_while(deposits, :ok, fn deposit, :ok ->
      # Internal: the credit of a deposit the chain holds.
      Purchase
      |> Ash.ActionInput.for_action(:credit_deposit, deposit, authorize?: false)
      |> Ash.run_action()
      |> case do
        {:ok, _purchase} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Another site's read already moved the cursor past this stretch.
  defp advance(cursor, from, to) do
    # Internal: moved by the Oban read once the stretch is credited.
    cursor
    |> Ash.Changeset.for_update(:advance, %{from: from, to: to}, authorize?: false)
    |> Ash.update()
    |> case do
      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} -> :ok
      result -> result
    end
  end

  # USDC has six decimals; Credits are kept to the millionth.
  defp amount(micro), do: Decimal.div(Decimal.new(micro), 1_000_000)

  # The purchase number a Buy step put in the deposit's last sixteen bytes.
  defp number(ref) do
    {:ok, number} = Ecto.UUID.load(<<rem(ref, Integer.pow(2, 128))::128>>)
    number
  end

  defp tag_word do
    {:ok, bytes} = Abi.bytes(Chains.source_tag())
    :binary.decode_unsigned(bytes)
  end
end

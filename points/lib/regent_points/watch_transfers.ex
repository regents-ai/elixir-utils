defmodule RegentPoints.WatchTransfers do
  @moduledoc """
  Oban owns scheduling/retries. A durable cursor advances in the same transaction
  as refresh jobs for sender and receiver accounts. A changed checkpoint stops
  processing for review; it never silently reprices ledger history.
  """
  use Oban.Worker,
    queue: :points_chain,
    max_attempts: 10,
    unique: [period: :infinity, states: :incomplete]

  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Nfts, RefreshHoldings, Store, TransferCursor}
  @impl true
  def perform(_) do
    if Nfts.tracking?(), do: scan(), else: :ok
  end

  defp scan do
    with {:ok, head} <- Nfts.block(:latest) do
      cursor =
        Points.start_cursor!(%{chain_id: 8453, next_block: head.number}, actor: Store.system())

      if cursor.stopped_at do
        {:cancel, :chain_history_changed}
      else
        check_and_scan(cursor, head)
      end
    end
  end

  defp check_and_scan(cursor, head) do
    case checkpoint(cursor) do
      :ok ->
        if cursor.next_block > head.number, do: :ok, else: scan(cursor, head)

      {:error, :checkpoint_changed} ->
        Points.stop_cursor!(cursor, %{stopped_at: max(0, cursor.next_block - 1)},
          actor: Store.system()
        )

        {:cancel, :chain_history_changed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp scan(cursor, head) do
    last = min(head.number, cursor.next_block + 999)

    with {:ok, block} <- Nfts.block(last),
         {:ok, wallets} <- Nfts.transfer_wallets(cursor.next_block, last),
         {:ok, same_block} <- Nfts.block(last),
         true <- block.hash == same_block.hash,
         {:ok, _} <- Ash.transact(TransferCursor, fn -> commit(cursor, block, wallets) end) do
      :ok
    else
      false ->
        {:error, :chain_changed_during_read}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp checkpoint(%{previous_hash: nil}), do: :ok

  defp checkpoint(cursor) do
    with {:ok, previous} <- Nfts.block(cursor.next_block - 1) do
      if previous.hash == cursor.previous_hash, do: :ok, else: {:error, :checkpoint_changed}
    end
  end

  defp commit(cursor, block, wallets) do
    query = TransferCursor |> Ash.Query.filter(id == ^cursor.id) |> Ash.Query.lock(:for_update)
    current = Points.read_cursors!(query: query, actor: Store.system()) |> List.first()

    if current.next_block == cursor.next_block and is_nil(current.stopped_at) do
      RegentPoints.accounts().wallet_holders(wallets)
      |> Enum.each(fn account ->
        %{account_id: account.id} |> RefreshHoldings.new() |> Oban.insert!()
      end)

      Points.advance_cursor!(current, %{next_block: block.number + 1, previous_hash: block.hash},
        actor: Store.system()
      )
    end

    :ok
  end
end

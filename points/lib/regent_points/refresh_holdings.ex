defmodule RegentPoints.RefreshHoldings do
  @moduledoc false
  use Oban.Worker,
    queue: :points_chain,
    max_attempts: 10,
    unique: [keys: [:account_id], period: :infinity, states: [:available, :scheduled, :retryable]]

  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Nfts, Store}
  @impl true
  def perform(%Oban.Job{args: %{"account_id" => id}}) do
    wallets = Store.human(id) |> Store.wallets()

    with {:ok, holdings} <- Nfts.latest(wallets),
         {:ok, result} <- Ash.transact(Account, fn -> save(id, wallets, holdings) end) do
      result
    end
  end

  defp save(id, wallets, holdings) do
    account = Store.lock_account(id)

    cond do
      wallets != Store.wallets(Store.human(id)) ->
        {:error, :wallets_changed}

      account.nft_block && account.nft_block > holdings.block ->
        :ok

      true ->
        Points.record_holdings!(
          account,
          %{
            nft_count: holdings.count,
            nft_block: holdings.block,
            nft_block_hash: holdings.hash,
            nft_checked_at: DateTime.utc_now(),
            wallet_digest: Nfts.wallet_digest(wallets)
          },
          actor: Store.system()
        )

        :ok
    end
  end
end

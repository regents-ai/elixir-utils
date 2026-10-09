defmodule RegentPoints.TallyAccount do
  @moduledoc """
  Writes one account's bonus for one ended program month: the points earned in that
  month times the tier its linked wallets hold at the tally. Waits while any of the
  month's actions is still being verified. Oban retries a Base outage.
  """
  use Oban.Worker,
    queue: :points_chain,
    max_attempts: 10,
    unique: [keys: [:account_id, :month], period: :infinity, states: :incomplete]

  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Bonus, Entry, Event, MonthBonus, Rules, Store}

  @impl true
  def perform(%Oban.Job{args: %{"account_id" => id, "month" => month}}) do
    {start, stop} = Rules.month(month)

    if pending?(id, start, stop) do
      {:snooze, 600}
    else
      # Base is read before the transaction; the account lock then guards the write.
      with {:ok, tier} <- Bonus.current(id),
           {:ok, _} <- Ash.transact(Account, fn -> record(id, month, {start, stop}, tier) end) do
        :ok
      end
    end
  end

  defp pending?(id, start, stop) do
    Event
    |> Ash.Query.filter(
      account_id == ^id and processing_status == :pending and source_action_at >= ^start and
        source_action_at < ^stop
    )
    |> Ash.Query.for_read(:read, %{}, actor: Store.system())
    |> Ash.exists?()
  end

  defp record(id, month, {start, stop}, tier) do
    Store.lock_account(id)
    program = Rules.program()

    existing =
      MonthBonus
      |> Ash.Query.filter(program_id == ^program and account_id == ^id and month == ^month)
      |> then(&Points.read_month_bonuses!(query: &1, actor: Store.system()))

    if existing == [] do
      earned = max(earned(id, program, start, stop), 0)

      Points.record_month_bonus!(
        %{
          program_id: program,
          account_id: id,
          month: month,
          earned_micro: earned,
          nft_count: tier.nft_count,
          nft_block: tier.block,
          bonus_percent: tier.percent,
          bonus_micro: div(earned * tier.percent, 100)
        },
        actor: Store.system()
      )
    end

    :ok
  end

  defp earned(id, program, start, stop) do
    Entry
    |> Ash.Query.filter(
      account_id == ^id and program_id == ^program and earned_at >= ^start and earned_at < ^stop
    )
    |> Ash.Query.for_read(:read, %{}, actor: Store.system())
    |> Ash.sum!(:points_micro_delta)
    |> Kernel.||(0)
  end
end

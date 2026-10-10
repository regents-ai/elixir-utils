defmodule RegentPoints.TallyPeriods do
  @moduledoc """
  Daily cron on the one designated owner site (Regents): queues one tally for each
  account that earned points in an ended 30-day program period and has no bonus for it yet.
  A tally that ran out of attempts is queued again by the next day's run.
  """
  use Oban.Worker,
    queue: :points,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  require Ash.Query
  alias RegentPoints.{Account, Rules, Store, TallyAccount}

  @impl true
  def perform(_job) do
    program = Rules.program()

    for period <- Rules.ended_periods(DateTime.utc_now()), id <- untallied(program, period) do
      Oban.insert!(TallyAccount.new(%{program_id: program, account_id: id, period: period}))
    end

    :ok
  end

  defp untallied(program, period) do
    {start, stop} = Rules.period(period)

    query =
      Account
      |> Ash.Query.filter(
        exists(entries, program_id == ^program and earned_at >= ^start and earned_at < ^stop) and
          not exists(period_bonuses, program_id == ^program and period == ^period)
      )
      |> Ash.Query.select([:id])

    query
    |> then(&RegentPoints.read_accounts!(query: &1, actor: Store.system()))
    |> Enum.map(& &1.id)
  end
end

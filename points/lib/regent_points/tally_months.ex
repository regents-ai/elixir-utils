defmodule RegentPoints.TallyMonths do
  @moduledoc """
  Daily cron on the one designated owner site (Regents): queues one tally for each
  account that earned points in an ended program month and has no bonus for it yet.
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

    for month <- Rules.ended_months(DateTime.utc_now()), id <- untallied(program, month) do
      Oban.insert!(TallyAccount.new(%{account_id: id, month: month}))
    end

    :ok
  end

  defp untallied(program, month) do
    {start, stop} = Rules.month(month)

    query =
      Account
      |> Ash.Query.filter(
        exists(entries, program_id == ^program and earned_at >= ^start and earned_at < ^stop) and
          not exists(month_bonuses, program_id == ^program and month == ^month)
      )
      |> Ash.Query.select([:id])

    query
    |> then(&RegentPoints.read_accounts!(query: &1, actor: Store.system()))
    |> Enum.map(& &1.id)
  end
end

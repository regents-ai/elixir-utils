defmodule RegentPoints.StartAwards do
  @moduledoc """
  Gives the one-time points for what an account has that Points has not recorded
  yet: the account, its linked X, GitHub and Farcaster accounts and its first
  paired agent (`RegentPoints.Rules.start_rules/0`), at most 80 points, without the
  person doing anything. What it had before the start earns at the start time;
  what came after the start earns at its real time, such as an account that joined
  after the start but before its site turned Points on.

  Every site with a start-rule source runs it from an hourly cron line. With no
  start time it stops, and after the last season's end too; before the start it
  waits for it. From the start it asks each approved start rule's source,
  `existing(rule_id, now)` with the run's own time, for what is there now, one
  `{account_id, reference}` per account, and records it through
  `RegentPoints.record_event/2` like any action, so the source still proves it and
  an account earns each rule once whichever site records it. The accounts that
  already have an event for the rule are read once per rule and left out.

  Unique for a day while queued or done, so it runs at most once a day, and each
  run records what no listener has.
  """
  use Oban.Worker,
    queue: :points,
    max_attempts: 5,
    unique: [period: {1, :day}, states: :successful]

  require Ash.Query
  alias RegentPoints.{Event, Rules, Store}

  @impl true
  def perform(_job) do
    now = DateTime.utc_now()

    case Keyword.get(Rules.config(), :starts_at) do
      nil -> {:cancel, :not_started}
      start -> at(now, DateTime.diff(start, now), DateTime.before?(now, Rules.ends_at()))
    end
  end

  defp at(_now, wait, _running?) when wait > 0, do: {:snooze, wait}
  defp at(_now, _wait, false), do: {:cancel, :ended}

  defp at(now, _wait, true) do
    for id <- Rules.start_rules(), Rules.enabled?(id), do: record_existing(id, now)
    :ok
  end

  defp record_existing(id, now) do
    recorded = recorded(id)

    for {account_id, reference} <- Rules.adapter(id).existing(id, now),
        not MapSet.member?(recorded, account_id) do
      {:ok, _} =
        RegentPoints.record_event(Map.put(reference, :rule_id, id), actor: Store.system())
    end
  end

  defp recorded(rule_id) do
    Event
    |> Ash.Query.filter(program_id == ^Rules.program() and rule_id == ^rule_id)
    |> Ash.Query.select([:account_id])
    |> Ash.Query.distinct([:account_id])
    |> Ash.read!(actor: Store.system())
    |> MapSet.new(& &1.account_id)
  end
end

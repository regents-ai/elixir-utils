defmodule RegentPoints.StartAwards do
  @moduledoc """
  Gives the one-time points for what an account already had when Points started:
  the account, its linked X, GitHub and Farcaster accounts and its first paired
  agent (`RegentPoints.Rules.start_rules/0`), at most 80 points, without the
  person doing anything. They earn at the start time.

  Every site runs it from an hourly cron line. With no start time it stops; before
  the start it waits for it. From the start it asks each approved start rule's
  source, `existing(rule_id, starts_at)`, for what was there before the start, one
  `{account_id, reference}` per account, and records
  it through `RegentPoints.record_event/2` like any action, so the source still
  proves it and an account earns each rule once whichever site records it. The
  accounts that already have an event for the rule are read once per rule and
  left out, and so are accounts agents opened for themselves, for the rules they
  are refused (`RegentPoints.Rules.closed_to_agent_opened?/1`).

  Unique while queued or done, so it runs once; after Oban prunes the finished
  job, the next run finds nothing new to record.
  """
  use Oban.Worker,
    queue: :points,
    max_attempts: 5,
    unique: [period: :infinity, states: :successful]

  require Ash.Query
  alias RegentPoints.{Event, HumanAccount, Rules, Store}

  @impl true
  def perform(_job) do
    case Keyword.get(Rules.config(), :starts_at) do
      nil -> {:cancel, :not_started}
      start -> at(start, DateTime.diff(start, DateTime.utc_now()))
    end
  end

  defp at(_start, wait) when wait > 0, do: {:snooze, wait}

  defp at(start, _wait) do
    for id <- Rules.start_rules(), Rules.enabled?(id), do: record_existing(id, start)
    :ok
  end

  defp record_existing(id, start) do
    left_out = MapSet.union(recorded(id), agent_opened(id))

    for {account_id, reference} <- Rules.adapter(id).existing(id, start),
        not MapSet.member?(left_out, account_id) do
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

  defp agent_opened(rule_id) do
    if Rules.closed_to_agent_opened?(rule_id) do
      HumanAccount
      |> Ash.Query.filter(agent_opened)
      |> Ash.Query.select([:id])
      |> Ash.read!(actor: Store.system())
      |> MapSet.new(& &1.id)
    else
      MapSet.new()
    end
  end
end

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
  proves it and an account earns each rule once whichever site records it. An
  account that already has an event for the rule is left out.

  Unique while queued or done, so it runs once; after Oban prunes the finished
  job, the next run finds nothing new to record.
  """
  use Oban.Worker,
    queue: :points,
    max_attempts: 5,
    unique: [period: :infinity, states: :successful]

  require Ash.Query
  alias RegentPoints.{Event, Rules, Store}

  @impl true
  def perform(_job) do
    case Keyword.get(Rules.config(), :starts_at) do
      nil -> {:cancel, :not_started}
      start -> at(start, DateTime.diff(start, DateTime.utc_now()))
    end
  end

  defp at(_start, wait) when wait > 0, do: {:snooze, wait}

  defp at(start, _wait) do
    for id <- Rules.start_rules(),
        Rules.enabled?(id),
        {account_id, reference} <- Rules.adapter(id).existing(id, start),
        not recorded?(account_id, id) do
      {:ok, _} =
        RegentPoints.record_event(Map.put(reference, :rule_id, id), actor: Store.system())
    end

    :ok
  end

  defp recorded?(account_id, rule_id) do
    Event
    |> Ash.Query.filter(
      program_id == ^Rules.program() and account_id == ^account_id and rule_id == ^rule_id
    )
    |> Ash.Query.for_read(:read, %{}, actor: Store.system())
    |> Ash.exists?()
  end
end

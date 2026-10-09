defmodule RegentPoints.Summary do
  @moduledoc "An owner-only read model containing no private source content or evidence URLs."
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, CapUsage, Entry, Event, MonthBonus, Rules, Store}

  @impl true
  def run(input, _, %{actor: actor}) do
    id = actor.human_account_id

    account_query =
      Account |> Ash.Query.filter(id == ^id) |> Ash.Query.load(:balance_micro)

    entries_query = Entry |> Ash.Query.filter(account_id == ^id) |> filters(input.arguments)
    today = DateTime.utc_now() |> DateTime.to_date()
    day_start = DateTime.new!(today, ~T[00:00:00])

    today_query =
      Entry
      |> Ash.Query.filter(account_id == ^id and earned_at >= ^day_start)
      |> Ash.Query.for_read(:read, %{}, actor: actor)

    pending_query =
      Event
      |> Ash.Query.filter(account_id == ^id and processing_status == :pending)
      |> Ash.Query.for_read(:read, %{}, actor: Store.system())

    cap_query =
      Ash.Query.filter(
        CapUsage,
        account_id == ^id and program_id == ^Rules.program() and window_start == ^today
      )

    bonuses_query =
      MonthBonus |> Ash.Query.filter(account_id == ^id) |> Ash.Query.sort(month: :desc)

    with {:ok, accounts} <- Points.read_accounts(query: account_query, actor: actor),
         {:ok, month_bonuses} <- Points.read_month_bonuses(query: bonuses_query, actor: actor),
         {:ok, entries} <- Points.history(query: entries_query, actor: actor),
         {:ok, today_points} <- Ash.sum(today_query, :points_micro_delta),
         {:ok, pending} <- Ash.count(pending_query),
         {:ok, caps} <- Points.read_caps(query: cap_query, actor: actor),
         {:ok, agent_names} <- agent_names(id, entries.results) do
      {:ok,
       %{
         balance_micro: balance(List.first(accounts)),
         earned_today_micro: today_points || 0,
         pending: pending,
         entries: entries.results,
         month_bonuses: month_bonuses,
         agent_names: agent_names,
         more?: entries.more?,
         allowances: allowances(caps)
       }}
    end
  end

  defp agent_names(id, entries) do
    ids =
      entries
      |> Enum.filter(&(&1.actor_kind == "agent"))
      |> Enum.map(& &1.actor_id)
      |> Enum.uniq()

    RegentPoints.accounts().agent_names(id, ids)
  end

  defp balance(nil), do: 0
  defp balance(account), do: account.balance_micro

  defp allowances(caps) do
    Enum.map(["credits", "activity:human", "activity:agent"], fn scope ->
      used =
        case Enum.find(caps, &(&1.cap_scope == scope)) do
          nil -> 0
          cap -> cap.points_micro
        end

      %{scope: scope, remaining: max(0, Rules.daily_cap(scope) - used)}
    end)
  end

  defp filters(query, filters) do
    query =
      if filters[:source_app],
        do: Ash.Query.filter(query, source_app == ^filters.source_app),
        else: query

    if filters[:actor_kind],
      do: Ash.Query.filter(query, actor_kind == ^filters.actor_kind),
      else: query
  end
end

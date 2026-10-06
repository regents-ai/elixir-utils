defmodule RegentCredits.AgentSpending do
  @moduledoc """
  Whether an agent may place a hold, under the settings its person saved in
  `RegentCredits.AgentPermission`. People spend without limits; an agent
  needs spending on, the site in its list, the amount within its most per
  spend, and its last 24 hours within its daily limit.

  Runs after the person's accounts are locked, so two holds by the same agent
  never both fit under the same room.
  """

  require Ash.Query

  alias RegentCredits.{Actor, AgentPermission, Hold}
  alias RegentCredits.Errors.Refused

  @spec allow(Actor.t(), map()) :: :ok | {:error, Exception.t()}
  def allow(%Actor{role: :agent} = actor, %{amount: amount}) do
    permission = permission(actor.privy_user_id, actor.agent_address)

    cond do
      is_nil(permission) or not permission.enabled ->
        refuse(:agent_off)

      actor.site not in permission.sites ->
        refuse(:agent_site)

      Decimal.gt?(amount, permission.max_per_spend) ->
        refuse(:agent_max_per_spend)

      Decimal.gt?(Decimal.add(spent_today(actor), amount), permission.daily_limit) ->
        refuse(:agent_daily_limit)

      true ->
        :ok
    end
  end

  def allow(%Actor{}, _details), do: :ok

  @doc """
  What the agent has held or spent in the last 24 hours: every hold it made,
  less what came back. A carried-over hold counts once, under its new key.
  """
  @spec spent_today(Actor.t()) :: Decimal.t()
  def spent_today(%Actor{privy_user_id: owner, agent_address: agent}) do
    since = DateTime.add(DateTime.utc_now(), -1, :day)

    # Internal: read while authorizing the agent's own hold.
    Hold
    |> Ash.Query.filter(
      privy_user_id == ^owner and agent_address == ^agent and inserted_at > ^since and
        status != :carried_over
    )
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(Decimal.new(0), fn hold, total ->
      total |> Decimal.add(hold.amount) |> Decimal.sub(hold.returned || 0)
    end)
  end

  defp permission(owner, agent) do
    # Internal: read while authorizing the agent's own hold.
    AgentPermission
    |> Ash.Query.filter(privy_user_id == ^owner and agent_address == ^agent)
    |> Ash.read_one!(authorize?: false)
  end

  defp refuse(reason), do: {:error, Refused.exception(reason: reason)}
end

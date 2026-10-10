defmodule RegentCredits.AgentSpending do
  @moduledoc """
  Whether an agent may place a hold, under the settings its person saved in
  `RegentCredits.AgentPermission`. People spend without limits; an agent
  needs spending on, the site in its list, the amount within its most per
  spend, and the owner's agent spending in the last 24 hours within its daily limit.

  Runs after the person's accounts are locked, so holds by different agents
  never both fit under the same room.
  """

  require Ash.Query

  alias RegentCredits.{Actor, AgentPermission, Hold}
  alias RegentCredits.Errors.Refused

  @spec allow(Actor.t(), map()) :: :ok | {:error, Exception.t()}
  def allow(%Actor{role: :agent} = actor, %{amount: amount}) do
    with :ok <- current_pairing(actor) do
      allow_amount(actor, amount)
    end
  end

  def allow(%Actor{}, _details), do: :ok

  defp allow_amount(actor, amount) do
    permission = permission(actor.privy_user_id, actor.agent_address)

    cond do
      is_nil(permission) or not permission.enabled or permission.pairing_id != actor.pairing_id ->
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

  @doc "Check the current episode inside the spending transaction, including idempotent retries."
  def current_pairing(%Actor{role: :agent, pairing_id: id} = actor) when is_binary(id) do
    case RegentAgents.Authority.lock(
           RegentCredits.repo(nil, :mutate),
           id,
           actor.privy_user_id,
           actor.agent_address
         ) do
      {:ok, _pairing} -> :ok
      {:error, _} -> refuse(:agent_not_paired)
    end
  end

  def current_pairing(%Actor{role: :agent}), do: refuse(:agent_not_paired)
  def current_pairing(%Actor{}), do: :ok

  @doc """
  What all the owner's agents have held or spent across sites in the last 24 hours,
  less what came back. A carried-over hold counts once, under its new key, at
  the time it was first held.
  """
  @spec spent_today(Actor.t()) :: Decimal.t()
  def spent_today(%Actor{} = actor) do
    # Internal usage for the owner already authorized by the hold action.
    actor |> usage_query() |> Ash.read!(authorize?: false) |> total_used()
  end

  @doc "The same owner-wide usage read, returning failures for display callers."
  @spec read_spent_today(Actor.t()) :: {:ok, Decimal.t()} | {:error, term()}
  def read_spent_today(%Actor{} = actor) do
    # Internal usage for the owner already authorized by the Budget action.
    with {:ok, holds} <- Ash.read(usage_query(actor), authorize?: false) do
      {:ok, total_used(holds)}
    end
  end

  defp usage_query(%Actor{privy_user_id: owner}) do
    since = DateTime.add(DateTime.utc_now(), -1, :day)

    # Internal: read while authorizing the agent's own hold.
    Hold
    |> Ash.Query.filter(
      privy_user_id == ^owner and not is_nil(agent_address) and held_at > ^since and
        status != :carried_over
    )
  end

  defp total_used(holds) do
    Enum.reduce(holds, Decimal.new(0), fn hold, total ->
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

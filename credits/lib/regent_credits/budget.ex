defmodule RegentCredits.Budget do
  @moduledoc """
  The current paired agent's spending settings and shared owner usage.

  This is a display snapshot, not authorization to spend. Holds still enforce
  the current pairing and limits inside their transaction. The separate
  grant-approval flag controls whether owners can enable grants; it does not
  turn an existing grant off.
  """
  use Ash.Resource,
    domain: RegentCredits,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    action :read, :map do
      run RegentCredits.Budget.Read
    end
  end

  policies do
    policy action(:read) do
      forbid_unless actor_attribute_equals(:role, :agent)

      authorize_if {RegentAgents.Checks.Paired,
                    repo_app: :regent_credits, wallet_field: :agent_address}
    end
  end
end

defmodule RegentCredits.Budget.Read do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  require Ash.Query

  alias RegentCredits.{Actor, AgentPermission, AgentSpending}

  @impl true
  def run(_input, _opts, %{actor: %Actor{role: :agent} = actor}) do
    query =
      AgentPermission
      |> Ash.Query.filter(
        privy_user_id == ^actor.privy_user_id and
          agent_address == ^actor.agent_address and pairing_id == ^actor.pairing_id
      )

    with {:ok, permission} <- Ash.read_one(query, actor: actor),
         {:ok, used} <- AgentSpending.read_spent_today(actor) do
      zero = Decimal.new(0)

      settings =
        if permission do
          Map.take(permission, [:enabled, :max_per_spend, :daily_limit, :sites])
        else
          %{enabled: false, max_per_spend: zero, daily_limit: zero, sites: []}
        end

      {:ok,
       Map.merge(settings, %{
         site_allowed: settings.enabled and actor.site in settings.sites,
         used_24h: used,
         remaining_24h: Decimal.max(Decimal.sub(settings.daily_limit, used), zero),
         grant_approvals_available: RegentCredits.agent_grants_enabled?()
       })}
    end
  end

  def run(_input, _opts, _context), do: {:error, Ash.Error.Forbidden.exception([])}
end

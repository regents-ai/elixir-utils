defmodule RegentCredits.History do
  @moduledoc "Owner-only pages of the permanent Credits ledger, including holds and returns."
  use Ash.Resource,
    domain: RegentCredits,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    action :history, :map do
      argument :after, :string, constraints: [max_length: 2_048]
      run RegentCredits.History.Read
    end
  end

  policies do
    policy action(:history) do
      authorize_if actor_attribute_equals(:role, :person)

      authorize_if {RegentAgents.Checks.Paired,
                    repo_app: :regent_credits, wallet_field: :agent_address}
    end
  end
end

defmodule RegentCredits.History.Read do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentCredits.Ledger
  alias RegentCredits.Ledger.{Account, Transfer}

  @impl true
  def run(input, _opts, %{actor: %RegentCredits.Actor{role: role, privy_user_id: owner}})
      when role in [:person, :agent] and is_binary(owner) do
    # The actor, never an input user id, determines the four private accounts.
    identifiers = Ledger.person(owner)

    accounts =
      Account
      |> Ash.Query.filter(identifier in ^identifiers)
      |> Ash.Query.select([:id, :identifier])
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, hd(String.split(&1.identifier, "/", parts: 2))})

    ids = Map.keys(accounts)

    page =
      [limit: 50] ++ if(input.arguments[:after], do: [after: input.arguments.after], else: [])

    # The authorized action has already resolved ownership. Related account
    # policies need not be bypassed or widened to reveal a counterparty.
    Transfer
    |> Ash.Query.filter(from_account_id in ^ids or to_account_id in ^ids)
    |> Ash.Query.sort(id: :desc)
    |> Ash.Query.for_read(:read_transfers)
    |> Ash.read(authorize?: false, page: page)
    |> case do
      {:ok, page} ->
        {:ok,
         %{
           entries: Enum.map(page.results, &entry(&1, accounts)),
           more?: page.more?,
           next: if(page.more?, do: List.last(page.results).__metadata__.keyset)
         }}

      {:error, _} = error ->
        error
    end
  end

  def run(_input, _opts, _context), do: {:error, Ash.Error.Forbidden.exception([])}

  defp entry(transfer, accounts) do
    from = accounts[transfer.from_account_id]
    to = accounts[transfer.to_account_id]
    amount = transfer.amount.amount

    %{
      id: transfer.id,
      at: transfer.timestamp,
      operation: transfer.operation,
      available_delta: delta(from, to, amount, ["given", "purchased"]),
      held_delta: delta(from, to, amount, ["held_given", "held_purchased"])
    }
  end

  defp delta(from, to, amount, kinds) do
    incoming = if to in kinds, do: amount, else: Decimal.new(0)
    outgoing = if from in kinds, do: amount, else: Decimal.new(0)
    Decimal.sub(incoming, outgoing)
  end
end

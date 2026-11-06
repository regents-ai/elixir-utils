defmodule RegentPoints.Leaderboard do
  @moduledoc """
  The ten highest totals, by public name, and the reader's own place among every
  account with points. A total and a public name are all that leave an account:
  no entry, wallet or account id. Any signed-in person or paired agent may read it.
  """
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Store}

  @size 10

  @impl true
  def run(_input, _, %{actor: actor}) do
    id = actor.human_account_id

    top_query =
      Account
      |> Ash.Query.filter(balance_micro > 0)
      |> Ash.Query.load(:balance_micro)
      |> Ash.Query.sort(balance_micro: :desc, id: :asc)
      |> Ash.Query.limit(@size)

    own_query = Account |> Ash.Query.filter(id == ^id) |> Ash.Query.load(:balance_micro)

    with {:ok, top} <- Points.read_accounts(query: top_query, actor: Store.system()),
         {:ok, own} <- Points.read_accounts(query: own_query, actor: Store.system()),
         {:ok, you} <- place(List.first(own)),
         {:ok, people} <- RegentPoints.accounts().people(Enum.map(top, & &1.id)) do
      {:ok, %{top: Enum.map(top, &row(&1, top, people, id)), you: you}}
    end
  end

  # Accounts level on points share a place: one more than the number ahead of them.
  defp row(account, top, people, reader) do
    people
    |> Map.fetch!(account.id)
    |> Map.take([:name, :squares, :picture])
    |> Map.merge(%{
      rank: Enum.count(top, &(&1.balance_micro > account.balance_micro)) + 1,
      points_micro: account.balance_micro,
      you?: account.id == reader
    })
  end

  defp place(%{balance_micro: balance}) when balance > 0 do
    ahead = Account |> Ash.Query.filter(balance_micro > ^balance)

    with {:ok, count} <- Ash.count(ahead, actor: Store.system()),
         do: {:ok, %{rank: count + 1, points_micro: balance}}
  end

  defp place(_account), do: {:ok, nil}
end

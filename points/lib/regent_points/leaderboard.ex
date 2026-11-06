defmodule RegentPoints.Leaderboard do
  @moduledoc """
  The board every reader of a site's Points page shares, read once for all of them
  under the system actor: the ten highest totals by public name, and every positive
  total, highest first, so `place/2` finds any reader's place without reading every
  account for each reader. Highest total first, then the lowest account id, so the
  order inside a tie is the same on every read.

  Each row carries its account id so the site can mark the reader's own row. The
  site keeps the ids and the list of totals on the server: a page or an agent gets
  the rows' names, pictures, places and totals, and its own place.
  """
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Store}

  @size 10

  @impl true
  def run(_input, _, _context) do
    query =
      Account
      |> Ash.Query.filter(balance_micro > 0)
      |> Ash.Query.select([:id])
      |> Ash.Query.load(:balance_micro)
      |> Ash.Query.sort(balance_micro: :desc, id: :asc)

    with {:ok, accounts} <- Points.read_accounts(query: query, actor: Store.system()),
         top = Enum.take(accounts, @size),
         {:ok, people} <- RegentPoints.accounts().people(Enum.map(top, & &1.id)) do
      totals = Enum.map(accounts, & &1.balance_micro)
      {:ok, %{top: Enum.map(top, &row(&1, totals, people)), totals: totals}}
    end
  end

  @doc """
  A reader's place among `totals`, highest first: one more than the number of totals
  strictly above theirs, so accounts level on points share a place. `nil` for a
  reader with no points, who has no place.
  """
  def place(totals, total) when is_integer(total) and total > 0,
    do: length(Enum.take_while(totals, &(&1 > total))) + 1

  def place(_totals, _total), do: nil

  defp row(account, totals, people) do
    people
    |> Map.fetch!(account.id)
    |> Map.take([:name, :squares, :picture])
    |> Map.merge(%{
      account_id: account.id,
      rank: place(totals, account.balance_micro),
      points_micro: account.balance_micro
    })
  end
end

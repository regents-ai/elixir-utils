defmodule RegentPoints.Bonus do
  @moduledoc """
  The approved NFT tiers. The bonus is never saved with an award: the tally at the
  end of each 30-day period applies the tier the account's linked wallets hold that day.
  """
  alias RegentPoints.{Nfts, Store}
  @tiers [{7, 75}, {3, 45}, {1, 20}]
  def tiers, do: @tiers
  def allowed_percentages, do: [0 | @tiers |> Enum.map(&elem(&1, 1)) |> Enum.sort()]

  def percent(count) do
    case Enum.find(@tiers, fn {minimum, _} -> count >= minimum end) do
      {_, percent} -> percent
      nil -> 0
    end
  end

  @doc "The tier the account's linked wallets hold now, read from Base and never saved."
  def current(account_id) do
    wallets = account_id |> Store.human() |> Store.wallets()

    with {:ok, holdings} <- Nfts.latest(wallets) do
      {:ok, %{nft_count: holdings.count, percent: percent(holdings.count), block: holdings.block}}
    end
  end
end

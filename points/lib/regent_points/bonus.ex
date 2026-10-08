defmodule RegentPoints.Bonus do
  @moduledoc "The approved NFT tiers, shared by awards, accounts and presentation."
  @tiers [{10, 75}, {5, 45}, {1, 20}]
  def tiers, do: @tiers
  def maximum, do: @tiers |> Enum.map(&elem(&1, 1)) |> Enum.max()
  def allowed_percentages, do: [0 | @tiers |> Enum.map(&elem(&1, 1)) |> Enum.sort()]

  def percent(count) when is_integer(count) do
    case Enum.find(@tiers, fn {minimum, _} -> count >= minimum end) do
      {_, percent} -> percent
      nil -> 0
    end
  end

  def percent(_), do: 0
end

defmodule RegentPoints.Bonus.Calculation do
  @moduledoc false
  use Ash.Resource.Calculation
  @impl true
  def load(_, _, _), do: [:nft_count]
  @impl true
  def calculate(records, _, _), do: Enum.map(records, &RegentPoints.Bonus.percent(&1.nft_count))
end

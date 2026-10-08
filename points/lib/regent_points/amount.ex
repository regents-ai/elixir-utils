defmodule RegentPoints.Amount do
  @moduledoc "Display points to two decimals without changing stored micro-points."
  def format(micro) when is_integer(micro) do
    micro
    |> Decimal.new()
    |> Decimal.div(1_000_000)
    |> Decimal.round(2, :down)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end

defmodule RegentPoints.Amount do
  @moduledoc "Display points the one Regent way without changing stored micro-points."
  def format(micro) when is_integer(micro),
    do: micro |> Decimal.new() |> Decimal.div(1_000_000) |> RegentFormat.amount()
end

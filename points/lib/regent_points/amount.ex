defmodule RegentPoints.Amount do
  @moduledoc "Display points the one Regent way without changing stored micro-points."

  # Stored amounts are whole micro-Points. Moving the decimal point six places is
  # exact at any size; `Decimal.div/2` would round past its 34-digit precision.
  def format(micro) when is_integer(micro),
    do: %{Decimal.new(micro) | exp: -6} |> RegentFormat.amount()
end

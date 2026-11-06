defmodule RegentPoints.AmountTest do
  use ExUnit.Case, async: true
  alias RegentPoints.Amount

  test "shows a Points amount exactly however many digits it has" do
    nines = String.duplicate("9", 35)
    grouped = nines |> RegentFormat.add_delimiters()
    micro = String.to_integer(nines <> "999999")

    assert Amount.format(micro) == grouped <> ".99"
    assert Amount.format(-micro) == "-" <> grouped <> ".99"
    assert Amount.format(1_234_567_891) == "1,234.56"
    assert Amount.format(400_000) == "0.400"
    assert Amount.format(0) == "0"
    assert Amount.format(35_000_000) == "35"
    assert Amount.format(1_250_000_000) == "1,250"
    assert Amount.format(35_500_000) == "35.50"
  end
end

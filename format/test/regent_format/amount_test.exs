defmodule RegentFormat.AmountTest do
  # Invariant (Sean, 27 Oct): an amount shown to a person has exactly two
  # decimals from 1 up and three significant digits below 1, and is never more
  # than the amount itself.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Decimal, as: D

  property "every token amount is shown in the one shape, never above its value" do
    check all(
            atoms <-
              one_of([integer(0..1_000), integer(0..1_000_000_000_000_000_000_000_000_000_000)]),
            decimals <- integer(0..24)
          ) do
      exact = D.new(1, atoms, -decimals)
      shown_text = RegentFormat.token_amount(atoms, decimals)
      shown = shown_text |> String.replace(",", "") |> D.new()

      assert D.compare(shown, exact) in [:lt, :eq]

      cond do
        D.eq?(exact, 0) ->
          assert shown_text == "0"

        D.lt?(exact, 1) ->
          assert shown_text =~ ~r/^0\.0*[1-9]\d\d$/
          last_place = shown_text |> String.split(".") |> List.last() |> String.length()
          assert D.lt?(D.sub(exact, shown), D.new(1, 1, -last_place))

        true ->
          assert shown_text =~ ~r/^\d{1,3}(,\d{3})*\.\d\d$/
          assert D.lt?(D.sub(exact, shown), D.new("0.01"))
      end
    end
  end

  test "Sean's examples and the edges of each shape" do
    assert RegentFormat.token_amount(41_450_907_949_459_360_601_917, 18) == "41,450.90"
    assert RegentFormat.amount(D.new("0.99951")) == "0.999"
    assert RegentFormat.amount(D.new("0.5")) == "0.500"
    assert RegentFormat.amount(D.new("1")) == "1.00"
    assert RegentFormat.amount(0) == "0"
    assert RegentFormat.amount(D.new("-1234.567")) == "-1,234.56"
  end
end

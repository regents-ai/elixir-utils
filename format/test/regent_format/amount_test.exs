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

  # Every amount, however large or long, is shown exactly: Decimal's own cut
  # toward zero, run at a precision wide enough for any value generated here.
  property "an amount of any size or sign is its exact value cut, never rounded up" do
    check all(
            coef <- integer(1..1_000_000_000_000_000_000),
            zeros <- integer(0..60),
            places <- integer(0..96),
            sign <- member_of([1, -1])
          ) do
      magnitude = D.new(1, coef * Integer.pow(10, zeros), -places)
      shown_text = RegentFormat.amount(%{magnitude | sign: sign})
      digits = shown_text |> String.trim_leading("-") |> String.replace(",", "")

      kept_places =
        if D.lt?(magnitude, 1),
          do: 2 - (length(Integer.digits(magnitude.coef)) + magnitude.exp - 1),
          else: 2

      assert digits ==
               D.to_string(wide(fn -> D.round(magnitude, kept_places, :down) end), :normal)

      assert String.starts_with?(shown_text, "-") == (sign == -1)
    end
  end

  property "a dollar amount of any size is Decimal's own half-up rounding, exactly" do
    check all(
            coef <- integer(0..1_000_000_000_000_000_000),
            zeros <- integer(0..60),
            scale <- integer(0..40),
            places <- integer(0..6),
            sign <- member_of([1, -1])
          ) do
      value = D.new(sign, coef * Integer.pow(10, zeros), -scale)
      rounded = D.to_string(wide(fn -> D.round(value, places) end), :normal)

      assert RegentFormat.format_currency(value, places) ==
               "$" <> RegentFormat.add_delimiters(rounded)
    end
  end

  test "amounts past 34 digits are shown exactly (they raised or rounded up before)" do
    assert RegentFormat.amount(D.new("1E32")) == "100,000,000,000,000,000,000,000,000,000,000.00"

    assert RegentFormat.token_amount(2 ** 256 - 1, 18) ==
             "115,792,089,237,316,195,423,570,985,008,687,907,853,269,984,665,640,564,039,457.58"

    assert RegentFormat.amount(D.new(-1, Integer.pow(10, 41) - 1, -40)) == "-9.99"
  end

  defp wide(fun), do: D.Context.with(%D.Context{precision: 1_000}, fun)

  test "Sean's examples and the edges of each shape" do
    assert RegentFormat.token_amount(41_450_907_949_459_360_601_917, 18) == "41,450.90"
    assert RegentFormat.amount(D.new("0.99951")) == "0.999"
    assert RegentFormat.amount(D.new("0.5")) == "0.500"
    assert RegentFormat.amount(D.new("1")) == "1.00"
    assert RegentFormat.amount(0) == "0"
    assert RegentFormat.amount(D.new("-1234.567")) == "-1,234.56"
  end
end

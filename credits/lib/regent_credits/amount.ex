defmodule RegentCredits.Amount do
  @moduledoc """
  Credits amounts. One Credit is one US dollar; the ledger keeps amounts to
  the millionth of a Credit (`XRC` with six digits) and people see them to
  the hundredth: "12.40 Credits".
  """

  @places 6

  @doc "True for a positive amount with at most six decimal places."
  @spec valid?(Decimal.t()) :: boolean()
  def valid?(amount), do: part?(amount) and Decimal.gt?(amount, 0)

  @doc "True for zero or a positive amount with at most six decimal places."
  @spec part?(Decimal.t()) :: boolean()
  def part?(%Decimal{} = amount),
    do:
      not Decimal.negative?(amount) and
        Decimal.eq?(Decimal.round(amount, @places, :down), amount)

  def part?(_amount), do: false

  @doc "The ledger's money value for an amount."
  @spec money(Decimal.t()) :: Money.t()
  def money(amount), do: Money.new!(:XRC, amount)

  @doc """
  The share of `amount` at `percent`, rounded down to the millionth. The rest
  of `amount` is what remains, so the two always add up.
  """
  @spec share(Decimal.t(), pos_integer()) :: Decimal.t()
  def share(amount, percent),
    do: amount |> Decimal.mult(percent) |> Decimal.div(100) |> Decimal.round(@places, :down)

  @doc "An amount as people read it, to the hundredth: \"12.40 Credits\"."
  @spec format(Decimal.t()) :: String.t()
  def format(amount) do
    shown = amount |> Decimal.round(2, :down) |> Decimal.to_string(:normal)

    case String.split(shown, ".") do
      [whole] -> "#{whole}.00 Credits"
      [whole, cents] -> "#{whole}.#{String.pad_trailing(cents, 2, "0")} Credits"
    end
  end
end

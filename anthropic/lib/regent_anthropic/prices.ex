defmodule RegentAnthropic.Prices do
  @moduledoc """
  Claude list prices in US dollars per million tokens, as published at
  platform.claude.com/docs/en/about-claude/pricing on 2026-10-12 (standard
  speed, global inference). Cache writes are the five-minute kind; this package
  never asks for the one-hour kind.

  A model missing from this table is refused before any request is sent, so no
  call goes unpriced. Update the table when Anthropic changes its prices.
  """

  @as_of ~D[2026-10-12]

  @per_million %{
    "claude-opus-5-5" => %{
      input: "4.00",
      cache_write: "5.00",
      cache_read: "0.20",
      output: "20.00"
    }
  }

  @prices Map.new(@per_million, fn {model, rates} ->
            {model, Map.new(rates, fn {kind, usd} -> {kind, Decimal.new(usd)} end)}
          end)

  @type t :: %{
          input: Decimal.t(),
          cache_write: Decimal.t(),
          cache_read: Decimal.t(),
          output: Decimal.t()
        }

  @doc "The date the table was taken from Anthropic's pricing page."
  @spec as_of() :: Date.t()
  def as_of, do: @as_of

  @doc "The models this package can price."
  @spec models() :: [String.t()]
  def models, do: @prices |> Map.keys() |> Enum.sort()

  @doc "The per-million-token prices for `model`."
  @spec fetch(String.t()) :: {:ok, t()} | :error
  def fetch(model), do: Map.fetch(@prices, model)

  @doc "The cost in US dollars of the billed tokens, given as `kind: count`."
  @spec cost(t(), keyword(non_neg_integer())) :: Decimal.t()
  def cost(prices, tokens) do
    Enum.reduce(tokens, Decimal.new(0), fn {kind, count}, total ->
      prices
      |> Map.fetch!(kind)
      |> Decimal.mult(count)
      |> Decimal.div(1_000_000)
      |> Decimal.add(total)
    end)
  end
end

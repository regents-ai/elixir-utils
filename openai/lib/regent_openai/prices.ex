defmodule RegentOpenAI.Prices do
  @moduledoc """
  OpenAI list prices in US dollars per million tokens, as published at
  developers.openai.com/api/docs/pricing on 2026-09-30 (standard processing,
  global endpoints).

  A model missing from this table is refused before any request is sent, so no
  call goes unpriced. Update the table when OpenAI changes its prices.
  """

  @as_of ~D[2026-09-30]

  @per_million %{
    "gpt-5.6-sol" => %{input: "4.00", cached_input: "0.40", output: "20.00"},
    "gpt-5.6-terra" => %{input: "2.00", cached_input: "0.20", output: "12.00"},
    "gpt-5.6-luna" => %{input: "0.20", cached_input: "0.02", output: "1.20"},
    "gpt-5.5" => %{input: "5.00", cached_input: "0.50", output: "30.00"},
    "gpt-5.4" => %{input: "2.50", cached_input: "0.25", output: "15.00"},
    "gpt-5.4-mini" => %{input: "0.75", cached_input: "0.075", output: "4.50"},
    "gpt-5.4-nano" => %{input: "0.20", cached_input: "0.02", output: "1.25"},
    "gpt-4o-transcribe" => %{input: "2.50", output: "10.00"},
    "gpt-4o-mini-transcribe" => %{input: "1.25", output: "5.00"},
    "gpt-4o-mini-tts" => %{input: "0.60", output: "12.00"}
  }

  @prices Map.new(@per_million, fn {model, rates} ->
            {model, Map.new(rates, fn {kind, usd} -> {kind, Decimal.new(usd)} end)}
          end)

  @type t :: %{
          required(:input) => Decimal.t(),
          required(:output) => Decimal.t(),
          optional(:cached_input) => Decimal.t()
        }

  @doc "The date the table was taken from OpenAI's pricing page."
  @spec as_of() :: Date.t()
  def as_of, do: @as_of

  @doc "The models this package can price."
  @spec models() :: [String.t()]
  def models, do: @prices |> Map.keys() |> Enum.sort()

  @doc "The per-million-token prices for `model`."
  @spec fetch(String.t()) :: {:ok, t()} | :error
  def fetch(model), do: Map.fetch(@prices, model)

  @doc """
  The cost in US dollars of the billed tokens, given as `kind: count` for the
  kinds the model is priced for.
  """
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

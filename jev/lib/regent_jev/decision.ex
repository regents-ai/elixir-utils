defmodule RegentJev.Decision do
  @moduledoc """
  Jev's answers to one call: for each question name, the key it chose and its
  confidence (0 to 1, or `nil` when Jev gave none).
  """

  @enforce_keys [:answers, :model, :usage, :cost_usd]
  defstruct [:answers, :model, :usage, :cost_usd]

  @type t :: %__MODULE__{
          answers: %{String.t() => %{choice: String.t(), confidence: float() | nil}},
          model: String.t(),
          usage: RegentJev.usage(),
          cost_usd: Decimal.t()
        }
end

defmodule RegentOpenAI.Transcript do
  @moduledoc "The text heard in a piece of audio."

  @enforce_keys [:text, :model, :usage, :cost_usd]
  defstruct [:text, :model, :usage, :cost_usd]

  @type t :: %__MODULE__{
          text: String.t(),
          model: String.t(),
          usage: RegentOpenAI.usage(),
          cost_usd: Decimal.t()
        }
end

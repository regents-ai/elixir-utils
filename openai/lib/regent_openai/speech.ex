defmodule RegentOpenAI.Speech do
  @moduledoc "Spoken audio for a piece of text."

  @enforce_keys [:audio, :content_type, :model, :usage, :cost_usd]
  defstruct [:audio, :content_type, :model, :usage, :cost_usd]

  @type t :: %__MODULE__{
          audio: binary(),
          content_type: String.t(),
          model: String.t(),
          usage: RegentOpenAI.usage(),
          cost_usd: Decimal.t()
        }
end

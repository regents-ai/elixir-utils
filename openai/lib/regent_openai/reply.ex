defmodule RegentOpenAI.Reply do
  @moduledoc "A text reply. `json` holds the decoded object when a schema was asked for."

  @enforce_keys [:text, :response_id, :model, :usage, :cost_usd]
  defstruct [:text, :json, :response_id, :model, :usage, :cost_usd]

  @type t :: %__MODULE__{
          text: String.t(),
          json: map() | nil,
          response_id: String.t(),
          model: String.t(),
          usage: RegentOpenAI.usage(),
          cost_usd: Decimal.t()
        }
end

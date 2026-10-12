defmodule RegentAnthropic.Reply do
  @moduledoc "A text reply. `json` holds the decoded object when a schema was asked for."

  @enforce_keys [:text, :message_id, :model, :usage, :cost_usd]
  defstruct [:text, :json, :message_id, :model, :usage, :cost_usd]

  @type t :: %__MODULE__{
          text: String.t(),
          json: map() | nil,
          message_id: String.t(),
          model: String.t(),
          usage: RegentAnthropic.usage(),
          cost_usd: Decimal.t()
        }
end

defmodule AgentEns.TxRequest do
  @moduledoc """
  Unsigned transaction payload that can be handed to a wallet or signer.
  """

  @enforce_keys [:to, :data, :value, :chain_id, :description]
  defstruct [:to, :data, :value, :chain_id, :description]

  @type t :: %__MODULE__{
          to: String.t(),
          data: String.t(),
          value: non_neg_integer(),
          chain_id: non_neg_integer(),
          description: String.t()
        }
end

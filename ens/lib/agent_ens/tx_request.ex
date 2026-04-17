defmodule AgentEns.TxRequest do
  @moduledoc """
  Unsigned request that can be handed to a wallet or signer.

  This struct is the handoff point between `ens_elixir` and the part of your
  app that actually asks for approval and sends the request.
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

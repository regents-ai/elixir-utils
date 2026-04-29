defmodule AgentWorld.TxRequest do
  @moduledoc """
  Unsigned request that can be handed to a wallet for AgentBook registration.
  """

  @enforce_keys [
    :to,
    :data,
    :value,
    :chain_id,
    :description,
    :expected_signer,
    :expires_at,
    :risk
  ]
  defstruct [:to, :data, :value, :chain_id, :description, :expected_signer, :expires_at, :risk]

  @type t :: %__MODULE__{
          to: String.t(),
          data: String.t(),
          value: String.t(),
          chain_id: non_neg_integer(),
          description: String.t(),
          expected_signer: String.t(),
          expires_at: String.t() | nil,
          risk: String.t()
        }
end

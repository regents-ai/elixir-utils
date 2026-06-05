defmodule KohakuProvider.Receipt do
  @moduledoc """
  Normalized transaction receipt.
  """

  alias KohakuProvider.Error

  @enforce_keys [:block_number, :status, :gas_used, :logs]
  defstruct [:block_number, :status, :gas_used, :logs]

  @type t :: %__MODULE__{
          block_number: non_neg_integer(),
          status: non_neg_integer(),
          gas_used: non_neg_integer(),
          logs: [map()]
        }

  @spec from_rpc(nil | map()) :: {:ok, t() | nil} | {:error, Error.t()}
  def from_rpc(nil), do: {:ok, nil}

  def from_rpc(%{"blockNumber" => block, "status" => status, "gasUsed" => gas_used} = receipt) do
    with {:ok, block} <- KohakuProvider.quantity_to_integer(block),
         {:ok, status} <- KohakuProvider.quantity_to_integer(status),
         {:ok, gas_used} <- KohakuProvider.quantity_to_integer(gas_used) do
      {:ok,
       %__MODULE__{
         block_number: block,
         status: status,
         gas_used: gas_used,
         logs: Map.get(receipt, "logs", [])
       }}
    end
  end

  def from_rpc(value),
    do: {:error, Error.rpc("invalid transaction receipt", %{value: inspect(value)})}
end

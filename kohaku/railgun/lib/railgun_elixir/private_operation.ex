defmodule RailgunElixir.PrivateOperation do
  @moduledoc """
  Prepared private Railgun operation.
  """

  alias RailgunElixir.TransactionBuilder

  @enforce_keys [:builder]
  defstruct [:builder, :native_amount, :to]

  @type t :: %__MODULE__{
          builder: TransactionBuilder.t(),
          native_amount: non_neg_integer() | nil,
          to: String.t() | nil
        }
end

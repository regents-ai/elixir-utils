defmodule KohakuProvider.Error do
  @moduledoc """
  Structured provider error.
  """

  @enforce_keys [:kind, :message]
  defstruct [:kind, :message, details: %{}]

  @type kind :: :invalid_argument | :rpc | :internal
  @type t :: %__MODULE__{kind: kind(), message: String.t(), details: map()}

  @spec invalid_argument(String.t(), map()) :: t()
  def invalid_argument(message, details \\ %{}),
    do: %__MODULE__{kind: :invalid_argument, message: message, details: details}

  @spec rpc(String.t(), map()) :: t()
  def rpc(message, details \\ %{}),
    do: %__MODULE__{kind: :rpc, message: message, details: details}

  @spec internal(String.t(), map()) :: t()
  def internal(message, details \\ %{}),
    do: %__MODULE__{kind: :internal, message: message, details: details}
end

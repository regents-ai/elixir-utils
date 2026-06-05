defmodule KohakuPlugins.Error do
  @moduledoc """
  Structured error returned by Kohaku plugin helper packages.
  """

  @enforce_keys [:kind, :message]
  defstruct [:kind, :message, details: %{}]

  @type kind :: :invalid_argument | :not_found | :storage | :keystore | :internal

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          details: map()
        }

  @spec invalid_argument(String.t(), map()) :: t()
  def invalid_argument(message, details \\ %{}),
    do: %__MODULE__{kind: :invalid_argument, message: message, details: details}

  @spec not_found(String.t(), map()) :: t()
  def not_found(message, details \\ %{}),
    do: %__MODULE__{kind: :not_found, message: message, details: details}

  @spec storage(String.t(), map()) :: t()
  def storage(message, details \\ %{}),
    do: %__MODULE__{kind: :storage, message: message, details: details}

  @spec keystore(String.t(), map()) :: t()
  def keystore(message, details \\ %{}),
    do: %__MODULE__{kind: :keystore, message: message, details: details}

  @spec internal(String.t(), map()) :: t()
  def internal(message, details \\ %{}),
    do: %__MODULE__{kind: :internal, message: message, details: details}
end

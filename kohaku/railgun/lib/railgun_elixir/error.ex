defmodule RailgunElixir.Error do
  @moduledoc """
  Structured error returned by Railgun Elixir.
  """

  @enforce_keys [:kind, :message]
  defstruct [:kind, :message, details: %{}]

  @type kind ::
          :invalid_argument
          | :not_found
          | :not_initialized
          | :unsupported
          | :rpc
          | :native
          | :internal

  @type t :: %__MODULE__{kind: kind(), message: String.t(), details: map()}

  @spec new(kind(), String.t(), map()) :: t()
  def new(kind, message, details \\ %{}),
    do: %__MODULE__{kind: kind, message: message, details: details}

  @spec invalid_argument(String.t(), map()) :: t()
  def invalid_argument(message, details \\ %{}), do: new(:invalid_argument, message, details)

  @spec not_found(String.t(), map()) :: t()
  def not_found(message, details \\ %{}), do: new(:not_found, message, details)

  @spec not_initialized(String.t(), map()) :: t()
  def not_initialized(message, details \\ %{}), do: new(:not_initialized, message, details)

  @spec unsupported(String.t(), map()) :: t()
  def unsupported(message, details \\ %{}), do: new(:unsupported, message, details)

  @spec rpc(String.t(), map()) :: t()
  def rpc(message, details \\ %{}), do: new(:rpc, message, details)

  @spec native(String.t(), map()) :: t()
  def native(message, details \\ %{}), do: new(:native, message, details)

  @spec internal(String.t(), map()) :: t()
  def internal(message, details \\ %{}), do: new(:internal, message, details)

  @spec from(term()) :: t()
  def from(%__MODULE__{} = error), do: error

  def from(%KohakuProvider.Error{} = error) do
    kind = if error.kind == :rpc, do: :rpc, else: :invalid_argument
    new(kind, error.message, error.details)
  end

  def from(%KohakuPlugins.Error{} = error) do
    kind =
      case error.kind do
        :not_found -> :not_found
        :internal -> :internal
        _kind -> :invalid_argument
      end

    new(kind, error.message, error.details)
  end

  def from(error), do: internal("unexpected error", %{reason: inspect(error)})
end

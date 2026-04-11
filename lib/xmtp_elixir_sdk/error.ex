defmodule XmtpElixirSdk.Error do
  @moduledoc """
  Structured SDK error used throughout the core modules.
  """

  @enforce_keys [:kind, :message]
  defstruct [:kind, :message, details: %{}]

  @type kind ::
          :not_found
          | :invalid_argument
          | :already_exists
          | :not_initialized
          | :unsupported
          | :conflict
          | :internal

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          details: map()
        }

  @spec new(kind(), String.t(), map()) :: t()
  def new(kind, message, details \\ %{}) when is_map(details) do
    %__MODULE__{kind: kind, message: message, details: details}
  end

  @spec not_found(String.t(), map()) :: t()
  def not_found(message, details \\ %{}), do: new(:not_found, message, details)

  @spec invalid_argument(String.t(), map()) :: t()
  def invalid_argument(message, details \\ %{}),
    do: new(:invalid_argument, message, details)

  @spec already_exists(String.t(), map()) :: t()
  def already_exists(message, details \\ %{}), do: new(:already_exists, message, details)

  @spec not_initialized(String.t(), map()) :: t()
  def not_initialized(message, details \\ %{}), do: new(:not_initialized, message, details)

  @spec unsupported(String.t(), map()) :: t()
  def unsupported(message, details \\ %{}), do: new(:unsupported, message, details)

  @spec conflict(String.t(), map()) :: t()
  def conflict(message, details \\ %{}), do: new(:conflict, message, details)

  @spec internal(String.t(), map()) :: t()
  def internal(message, details \\ %{}), do: new(:internal, message, details)
end

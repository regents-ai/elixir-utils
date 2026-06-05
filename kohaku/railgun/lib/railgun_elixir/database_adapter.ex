defmodule RailgunElixir.DatabaseAdapter do
  @moduledoc """
  Prefixes host storage keys for Railgun state.
  """

  alias KohakuPlugins.Host

  @enforce_keys [:prefix, :host]
  defstruct [:prefix, :host]

  @type t :: %__MODULE__{prefix: String.t(), host: Host.t()}

  @spec new(String.t(), Host.t()) :: t()
  def new(prefix, %Host{} = host) when is_binary(prefix),
    do: %__MODULE__{prefix: prefix, host: host}

  @spec get(t(), String.t()) :: {:ok, String.t() | nil} | {:error, KohakuPlugins.Error.t()}
  def get(%__MODULE__{} = adapter, key),
    do: Host.storage_get(adapter.host, storage_key(adapter, key))

  @spec set(t(), String.t(), String.t()) :: :ok | {:error, KohakuPlugins.Error.t()}
  def set(%__MODULE__{} = adapter, key, value),
    do: Host.storage_set(adapter.host, storage_key(adapter, key), value)

  @spec delete(t(), String.t()) :: :ok | {:error, KohakuPlugins.Error.t()}
  def delete(%__MODULE__{} = adapter, key), do: set(adapter, key, "")

  defp storage_key(%__MODULE__{prefix: prefix}, key), do: "#{prefix}:#{key}"
end

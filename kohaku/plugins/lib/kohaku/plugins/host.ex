defmodule KohakuPlugins.Host do
  @moduledoc """
  Host container passed into protocol plugins.
  """

  @enforce_keys [:storage, :keystore, :provider]
  defstruct [:storage, :storage_module, :keystore, :keystore_module, :provider, :network]

  @type t :: %__MODULE__{
          storage: term(),
          storage_module: module(),
          keystore: term(),
          keystore_module: module(),
          provider: term(),
          network: term()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      storage: Keyword.fetch!(opts, :storage),
      storage_module: Keyword.get(opts, :storage_module, KohakuPlugins.MemoryStorage),
      keystore: Keyword.fetch!(opts, :keystore),
      keystore_module: Keyword.get(opts, :keystore_module, KohakuPlugins.StaticKeystore),
      provider: Keyword.fetch!(opts, :provider),
      network: Keyword.get(opts, :network)
    }
  end

  @spec storage_get(t(), String.t()) ::
          {:ok, String.t() | nil} | {:error, KohakuPlugins.Error.t()}
  def storage_get(%__MODULE__{} = host, key), do: host.storage_module.get(host.storage, key)

  @spec storage_set(t(), String.t(), String.t()) :: :ok | {:error, KohakuPlugins.Error.t()}
  def storage_set(%__MODULE__{} = host, key, value),
    do: host.storage_module.set(host.storage, key, value)

  @spec derive_at(t(), String.t()) :: {:ok, String.t()} | {:error, KohakuPlugins.Error.t()}
  def derive_at(%__MODULE__{} = host, path),
    do: host.keystore_module.derive_at(host.keystore, path)
end

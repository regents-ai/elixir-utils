defmodule RailgunElixir.Builder do
  @moduledoc """
  Builder for native Railgun providers.
  """

  alias RailgunElixir.{ChainConfig, Error, Native, Provider, Runtime, UtxoSyncer}

  @enforce_keys [:runtime, :chain, :provider]
  defstruct [:runtime, :chain, :provider, :utxo_syncer, poi: false, rpc_batch_size: 10]

  @type t :: %__MODULE__{
          runtime: Runtime.t(),
          chain: ChainConfig.t(),
          provider: KohakuProvider.t(),
          utxo_syncer: UtxoSyncer.t() | nil,
          poi: boolean(),
          rpc_batch_size: pos_integer()
        }

  @spec new(Runtime.t() | atom(), ChainConfig.t(), KohakuProvider.t()) ::
          {:ok, t()} | {:error, Error.t()}
  def new(runtime, %ChainConfig{} = chain, %KohakuProvider{} = provider) do
    {:ok, %__MODULE__{runtime: Runtime.new(runtime), chain: chain, provider: provider}}
  end

  @spec with_utxo_syncer(t(), UtxoSyncer.t()) :: t()
  def with_utxo_syncer(%__MODULE__{} = builder, %UtxoSyncer{} = syncer) do
    %{builder | utxo_syncer: syncer, rpc_batch_size: UtxoSyncer.rpc_batch_size(syncer, 10)}
  end

  @spec with_poi(t()) :: t()
  def with_poi(%__MODULE__{} = builder), do: %{builder | poi: true}

  @spec build(t()) :: {:ok, Provider.t()} | {:error, Error.t()}
  def build(%__MODULE__{} = builder) do
    with {:ok, record} <-
           Native.request(builder.runtime, "provider_create", %{
             chain_id: builder.chain.id,
             rpc_url: builder.provider.rpc_url,
             rpc_batch_size: builder.rpc_batch_size,
             poi: builder.poi
           }) do
      {:ok,
       %Provider{
         runtime: builder.runtime,
         id: record["id"],
         chain: builder.chain,
         rpc_url: builder.provider.rpc_url
       }}
    end
  end
end

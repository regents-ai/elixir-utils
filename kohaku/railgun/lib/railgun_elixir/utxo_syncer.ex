defmodule RailgunElixir.UtxoSyncer do
  @moduledoc """
  UTXO syncer configuration.
  """

  alias RailgunElixir.ChainConfig

  defstruct [:type, :chain, :provider, :batch_size, syncers: []]

  @type t :: %__MODULE__{
          type: :subsquid | :rpc | :chained,
          chain: ChainConfig.t() | nil,
          provider: KohakuProvider.t() | nil,
          batch_size: pos_integer() | nil,
          syncers: [t()]
        }

  @spec subsquid(ChainConfig.t()) :: t()
  def subsquid(%ChainConfig{} = chain), do: %__MODULE__{type: :subsquid, chain: chain}

  @spec rpc(ChainConfig.t(), KohakuProvider.t(), pos_integer()) :: t()
  def rpc(%ChainConfig{} = chain, %KohakuProvider{} = provider, batch_size)
      when is_integer(batch_size) and batch_size > 0 do
    %__MODULE__{type: :rpc, chain: chain, provider: provider, batch_size: batch_size}
  end

  @spec chained([t()]) :: t()
  def chained(syncers) when is_list(syncers), do: %__MODULE__{type: :chained, syncers: syncers}

  @spec rpc_batch_size(t() | nil, pos_integer()) :: pos_integer()
  def rpc_batch_size(nil, default), do: default

  def rpc_batch_size(%__MODULE__{type: :rpc, batch_size: batch_size}, _default), do: batch_size

  def rpc_batch_size(%__MODULE__{type: :chained, syncers: syncers}, default) do
    syncers
    |> Enum.find(&(&1.type == :rpc))
    |> rpc_batch_size(default)
  end

  def rpc_batch_size(%__MODULE__{}, default), do: default
end

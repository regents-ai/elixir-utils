defmodule RailgunElixir.Provider do
  @moduledoc """
  Native Railgun provider handle.
  """

  alias KohakuPlugins.{Asset, AssetAmount}
  alias RailgunElixir.{Error, Native, Runtime, ShieldBuilder, Signer, TransactionBuilder}

  @enforce_keys [:runtime, :id, :chain, :rpc_url]
  defstruct [:runtime, :id, :chain, :rpc_url]

  @type t :: %__MODULE__{
          runtime: Runtime.t(),
          id: String.t(),
          chain: RailgunElixir.ChainConfig.t(),
          rpc_url: String.t()
        }

  @spec register(t(), Signer.t()) :: :ok | {:error, Error.t()}
  def register(%__MODULE__{} = provider, %Signer{} = signer) do
    with {:ok, _result} <-
           Native.request(provider.runtime, "provider_register", %{
             provider_id: provider.id,
             signer_id: signer.id
           }) do
      :ok
    end
  end

  @spec sync(t()) :: :ok | {:error, Error.t()}
  def sync(%__MODULE__{} = provider) do
    with {:ok, _result} <-
           Native.request(provider.runtime, "provider_sync", %{provider_id: provider.id}) do
      :ok
    end
  end

  @spec balance(t(), String.t()) :: {:ok, [AssetAmount.t()]} | {:error, Error.t()}
  def balance(%__MODULE__{} = provider, address) when is_binary(address) do
    with {:ok, %{"balances" => balances}} <-
           Native.request(provider.runtime, "provider_balance", %{
             provider_id: provider.id,
             address: address
           }) do
      balances
      |> Enum.map(&asset_amount_from_native/1)
      |> collect()
    end
  end

  @spec shield(t()) :: ShieldBuilder.t()
  def shield(%__MODULE__{} = provider), do: ShieldBuilder.new(provider)

  @spec transact(t()) :: TransactionBuilder.t()
  def transact(%__MODULE__{} = provider), do: TransactionBuilder.new(provider)

  @spec build(t(), TransactionBuilder.t()) ::
          {:ok, KohakuProvider.TxData.t()} | {:error, Error.t()}
  def build(%__MODULE__{} = provider, %TransactionBuilder{} = builder) do
    with {:ok, tx} <-
           Native.request(
             provider.runtime,
             "transaction_build",
             %{
               provider_id: provider.id,
               operations: TransactionBuilder.to_native_operations(builder)
             },
             600_000
           ) do
      case KohakuProvider.TxData.from(tx) do
        {:ok, tx} -> {:ok, tx}
        {:error, error} -> {:error, Error.from(error)}
      end
    end
  end

  defp asset_amount_from_native(%{"asset" => asset, "amount" => amount}) do
    with {:ok, asset} <- Asset.from_native_map(asset),
         {amount, ""} <- Integer.parse(to_string(amount)) do
      AssetAmount.new(asset, amount)
    else
      {:error, error} ->
        {:error, Error.from(error)}

      _error ->
        {:error, Error.native("invalid native balance", %{asset: asset, amount: amount})}
    end
  end

  defp collect(results), do: collect(results, [])

  defp collect([{:ok, value} | rest], acc), do: collect(rest, [value | acc])
  defp collect([{:error, error} | _rest], _acc), do: {:error, error}
  defp collect([], acc), do: {:ok, Enum.reverse(acc)}
end

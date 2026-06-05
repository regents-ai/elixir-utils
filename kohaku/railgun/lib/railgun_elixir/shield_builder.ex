defmodule RailgunElixir.ShieldBuilder do
  @moduledoc """
  Builder for Railgun shield transactions.
  """

  alias KohakuPlugins.Asset
  alias RailgunElixir.{Error, Native, Provider}

  @enforce_keys [:provider]
  defstruct [:provider, operations: []]

  @type operation ::
          {:shield, String.t(), Asset.t(), non_neg_integer()}
          | {:shield_native, String.t(), non_neg_integer()}

  @type t :: %__MODULE__{provider: Provider.t(), operations: [operation()]}

  @spec new(Provider.t()) :: t()
  def new(%Provider{} = provider), do: %__MODULE__{provider: provider}

  @spec shield(t(), String.t(), Asset.t(), non_neg_integer()) :: t()
  def shield(%__MODULE__{} = builder, recipient, %Asset{} = asset, value)
      when is_binary(recipient) and is_integer(value) and value >= 0 do
    %{builder | operations: builder.operations ++ [{:shield, recipient, asset, value}]}
  end

  @spec shield_native(t(), String.t(), non_neg_integer()) :: t()
  def shield_native(%__MODULE__{} = builder, recipient, value)
      when is_binary(recipient) and is_integer(value) and value >= 0 do
    %{builder | operations: builder.operations ++ [{:shield_native, recipient, value}]}
  end

  @spec build(t()) :: {:ok, [KohakuProvider.TxData.t()]} | {:error, Error.t()}
  def build(%__MODULE__{} = builder) do
    with {:ok, %{"transactions" => txs}} <-
           Native.request(
             builder.provider.runtime,
             "shield_build",
             %{
               provider_id: builder.provider.id,
               operations: to_native_operations(builder)
             },
             600_000
           ) do
      txs
      |> Enum.map(&KohakuProvider.TxData.from/1)
      |> Enum.map(&normalize_tx_result/1)
      |> collect()
    end
  end

  @spec to_native_operations(t()) :: [map()]
  def to_native_operations(%__MODULE__{} = builder) do
    Enum.map(builder.operations, fn
      {:shield, recipient, asset, value} ->
        %{
          "type" => "shield",
          "recipient" => recipient,
          "asset" => Asset.to_native_map(asset),
          "amount" => Integer.to_string(value)
        }

      {:shield_native, recipient, value} ->
        %{
          "type" => "shield_native",
          "recipient" => recipient,
          "amount" => Integer.to_string(value)
        }
    end)
  end

  defp collect(results), do: collect(results, [])

  defp collect([{:ok, value} | rest], acc), do: collect(rest, [value | acc])
  defp collect([{:error, error} | _rest], _acc), do: {:error, error}
  defp collect([], acc), do: {:ok, Enum.reverse(acc)}

  defp normalize_tx_result({:ok, tx}), do: {:ok, tx}
  defp normalize_tx_result({:error, error}), do: {:error, Error.from(error)}
end

defmodule RailgunElixir.TransactionBuilder do
  @moduledoc """
  Builder for private Railgun transfers and unshields.
  """

  alias KohakuPlugins.Asset
  alias RailgunElixir.{Provider, Signer}

  @enforce_keys [:provider]
  defstruct [:provider, operations: []]

  @type operation ::
          {:transfer, Signer.t(), String.t(), Asset.t(), non_neg_integer(), String.t()}
          | {:unshield, Signer.t(), String.t(), Asset.t(), non_neg_integer()}

  @type t :: %__MODULE__{provider: Provider.t(), operations: [operation()]}

  @spec new(Provider.t()) :: t()
  def new(%Provider{} = provider), do: %__MODULE__{provider: provider}

  @spec transfer(t(), Signer.t(), String.t(), Asset.t(), non_neg_integer(), String.t()) :: t()
  def transfer(%__MODULE__{} = builder, %Signer{} = from, to, %Asset{} = asset, value, memo \\ "")
      when is_binary(to) and is_integer(value) and value >= 0 and is_binary(memo) do
    %{builder | operations: builder.operations ++ [{:transfer, from, to, asset, value, memo}]}
  end

  @spec unshield(t(), Signer.t(), String.t(), Asset.t(), non_neg_integer()) :: t()
  def unshield(%__MODULE__{} = builder, %Signer{} = from, to, %Asset{} = asset, value)
      when is_binary(to) and is_integer(value) and value >= 0 do
    %{builder | operations: builder.operations ++ [{:unshield, from, to, asset, value}]}
  end

  @spec to_native_operations(t()) :: [map()]
  def to_native_operations(%__MODULE__{} = builder) do
    Enum.map(builder.operations, fn
      {:transfer, from, to, asset, value, memo} ->
        %{
          "type" => "transfer",
          "from_signer_id" => from.id,
          "to" => to,
          "asset" => Asset.to_native_map(asset),
          "amount" => Integer.to_string(value),
          "memo" => memo
        }

      {:unshield, from, to, asset, value} ->
        %{
          "type" => "unshield",
          "from_signer_id" => from.id,
          "to" => to,
          "asset" => Asset.to_native_map(asset),
          "amount" => Integer.to_string(value)
        }
    end)
  end
end

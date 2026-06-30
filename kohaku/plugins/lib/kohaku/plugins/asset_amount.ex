defmodule KohakuPlugins.AssetAmount do
  @moduledoc """
  Amount of a Kohaku asset.
  """

  alias KohakuPlugins.{Asset, Error}

  @enforce_keys [:asset, :amount]
  defstruct [:asset, :amount, :tag]

  @type t :: %__MODULE__{
          asset: Asset.t(),
          amount: non_neg_integer(),
          tag: String.t() | nil
        }

  @spec new(Asset.t(), non_neg_integer(), String.t() | nil) :: {:ok, t()} | {:error, Error.t()}
  def new(asset, amount, tag \\ nil)

  def new(%Asset{} = asset, amount, tag)
      when is_integer(amount) and amount >= 0 and (is_binary(tag) or is_nil(tag)) do
    {:ok, %__MODULE__{asset: asset, amount: amount, tag: tag}}
  end

  def new(%Asset{}, amount, _tag) do
    {:error, Error.invalid_argument("amount must be a non-negative integer", %{value: amount})}
  end

  def new(asset, _amount, _tag) do
    {:error, Error.invalid_argument("asset is invalid", %{value: inspect(asset)})}
  end

  @spec to_native_map(t()) :: map()
  def to_native_map(%__MODULE__{asset: asset, amount: amount, tag: nil}) do
    %{"asset" => Asset.to_native_map(asset), "amount" => Integer.to_string(amount)}
  end

  def to_native_map(%__MODULE__{asset: asset, amount: amount, tag: tag}) do
    %{
      "asset" => Asset.to_native_map(asset),
      "amount" => Integer.to_string(amount),
      "tag" => tag
    }
  end

  @spec from_native_map(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_native_map(%{"asset" => asset, "amount" => amount} = input) do
    with {:ok, asset} <- Asset.from_native_map(asset),
         {amount, ""} <- Integer.parse(to_string(amount)) do
      tag =
        case Map.get(input, "tag") do
          value when is_binary(value) and value != "" -> value
          _value -> nil
        end

      new(asset, amount, tag)
    else
      _error ->
        {:error, Error.invalid_argument("invalid asset amount", %{value: inspect(input)})}
    end
  end

  def from_native_map(value),
    do: {:error, Error.invalid_argument("invalid asset amount", %{value: inspect(value)})}
end

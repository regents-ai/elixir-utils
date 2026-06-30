defmodule RailgunElixir.Note do
  @moduledoc """
  Unspent Railgun note metadata returned by the native provider.
  """

  alias KohakuPlugins.Asset
  alias RailgunElixir.Error

  @enforce_keys [
    :asset,
    :amount,
    :tree_number,
    :leaf_index,
    :blinded_commitment,
    :commitment_type,
    :memo
  ]
  defstruct [
    :asset,
    :amount,
    :poi_status,
    :tree_number,
    :leaf_index,
    :blinded_commitment,
    :commitment_type,
    :memo,
    :address
  ]

  @type t :: %__MODULE__{
          asset: Asset.t(),
          amount: non_neg_integer(),
          poi_status: String.t() | nil,
          tree_number: non_neg_integer(),
          leaf_index: non_neg_integer(),
          blinded_commitment: String.t(),
          commitment_type: String.t(),
          memo: String.t(),
          address: String.t() | nil
        }

  @spec from_native(map(), String.t() | nil) :: {:ok, t()} | {:error, Error.t()}
  def from_native(%{"asset" => asset, "amount" => amount} = record, address \\ nil) do
    with {:ok, asset} <- Asset.from_native_map(asset),
         {amount, ""} <- Integer.parse(to_string(amount)) do
      {:ok,
       %__MODULE__{
         asset: asset,
         amount: amount,
         poi_status: record["poi_status"],
         tree_number: record["tree_number"],
         leaf_index: record["leaf_index"],
         blinded_commitment: record["blinded_commitment"],
         commitment_type: record["commitment_type"],
         memo: record["memo"] || "",
         address: address
       }}
    else
      {:error, error} ->
        {:error, Error.from(error)}

      _error ->
        {:error, Error.native("invalid native note", %{value: inspect(record)})}
    end
  end
end

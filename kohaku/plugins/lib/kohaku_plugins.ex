defmodule KohakuPlugins do
  @moduledoc """
  Shared host primitives for Kohaku Elixir protocol packages.

  The package intentionally stays small. Protocol packages define their own
  behavior; this package only supplies common shapes for assets, balances,
  storage, keystores, hosts, and broadcasters.
  """

  alias KohakuPlugins.{Asset, AssetAmount}

  @doc """
  Builds a native asset identifier.
  """
  @spec native_asset() :: Asset.t()
  def native_asset, do: Asset.native()

  @doc """
  Builds an ERC-20 asset identifier.
  """
  @spec erc20(String.t()) :: {:ok, Asset.t()} | {:error, KohakuPlugins.Error.t()}
  def erc20(contract), do: Asset.erc20(contract)

  @doc """
  Builds an asset amount.
  """
  @spec asset_amount(Asset.t(), non_neg_integer(), String.t() | nil) ::
          {:ok, AssetAmount.t()} | {:error, KohakuPlugins.Error.t()}
  def asset_amount(asset, amount, tag \\ nil), do: AssetAmount.new(asset, amount, tag)
end

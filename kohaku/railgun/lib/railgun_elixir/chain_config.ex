defmodule RailgunElixir.ChainConfig do
  @moduledoc """
  Railgun chain configuration.
  """

  @enforce_keys [
    :id,
    :railgun_smart_wallet,
    :unshield_fee_bps,
    :relay_adapt_contract,
    :wrapped_base_token,
    :deployment_block,
    :poi_start_block,
    :subsquid_endpoint,
    :poi_endpoint,
    :list_keys,
    :privacy_paymaster,
    :railgun_fee_adapter
  ]
  defstruct [
    :id,
    :railgun_smart_wallet,
    :unshield_fee_bps,
    :relay_adapt_contract,
    :wrapped_base_token,
    :deployment_block,
    :poi_start_block,
    :subsquid_endpoint,
    :poi_endpoint,
    :list_keys,
    :privacy_paymaster,
    :railgun_fee_adapter
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          railgun_smart_wallet: String.t(),
          unshield_fee_bps: non_neg_integer(),
          relay_adapt_contract: String.t(),
          wrapped_base_token: String.t(),
          deployment_block: non_neg_integer(),
          poi_start_block: non_neg_integer(),
          subsquid_endpoint: String.t(),
          poi_endpoint: String.t(),
          list_keys: [String.t()],
          privacy_paymaster: String.t() | nil,
          railgun_fee_adapter: String.t() | nil
        }

  @spec from_native(map()) :: t()
  def from_native(record) when is_map(record) do
    %__MODULE__{
      id: record["id"],
      railgun_smart_wallet: record["railgun_smart_wallet"],
      unshield_fee_bps: record["unshield_fee_bps"],
      relay_adapt_contract: record["relay_adapt_contract"],
      wrapped_base_token: record["wrapped_base_token"],
      deployment_block: record["deployment_block"],
      poi_start_block: record["poi_start_block"],
      subsquid_endpoint: record["subsquid_endpoint"],
      poi_endpoint: record["poi_endpoint"],
      list_keys: record["list_keys"] || [],
      privacy_paymaster: record["privacy_paymaster"],
      railgun_fee_adapter: record["railgun_fee_adapter"]
    }
  end

  @spec to_native(t()) :: map()
  def to_native(%__MODULE__{} = chain) do
    %{
      "id" => chain.id,
      "railgun_smart_wallet" => chain.railgun_smart_wallet,
      "unshield_fee_bps" => chain.unshield_fee_bps,
      "relay_adapt_contract" => chain.relay_adapt_contract,
      "wrapped_base_token" => chain.wrapped_base_token,
      "deployment_block" => chain.deployment_block,
      "poi_start_block" => chain.poi_start_block,
      "subsquid_endpoint" => chain.subsquid_endpoint,
      "poi_endpoint" => chain.poi_endpoint,
      "list_keys" => chain.list_keys,
      "privacy_paymaster" => chain.privacy_paymaster,
      "railgun_fee_adapter" => chain.railgun_fee_adapter
    }
  end
end

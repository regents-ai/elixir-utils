defmodule XmtpElixirSdk.Constants do
  @moduledoc """
  Public URL constants and metadata helpers for the SDK surface.
  """

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types

  @spec api_urls() :: %{optional(Types.env()) => String.t()}
  def api_urls do
    %{
      local: Types.api_url(:local),
      dev: Types.api_url(:dev),
      production: Types.api_url(:production),
      testnet_staging: Types.api_url(:testnet_staging),
      testnet_dev: Types.api_url(:testnet_dev),
      testnet: Types.api_url(:testnet),
      mainnet: Types.api_url(:mainnet)
    }
  end

  @spec history_sync_urls() :: %{optional(Types.env()) => String.t()}
  def history_sync_urls do
    %{
      local: Types.history_sync_url(:local),
      dev: Types.history_sync_url(:dev),
      production: Types.history_sync_url(:production),
      testnet_staging: Types.history_sync_url(:testnet_staging),
      testnet_dev: Types.history_sync_url(:testnet_dev),
      testnet: Types.history_sync_url(:testnet),
      mainnet: Types.history_sync_url(:mainnet)
    }
  end

  @spec metadata_field_name(Types.metadata_field()) :: String.t()
  def metadata_field_name(field), do: Types.metadata_field_name(field)

  @spec metadata_field_from_name(String.t()) ::
          {:ok, Types.metadata_field()} | {:error, Error.t()}
  def metadata_field_from_name(name), do: Types.metadata_field_from_name(name)
end

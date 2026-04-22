defmodule XmtpElixirSdk.Constants do
  @moduledoc """
  Public URL constants and metadata helpers for the SDK surface.
  """

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types

  @envs [:local, :dev, :production, :testnet_staging, :testnet_dev, :testnet, :mainnet]

  @spec api_urls() :: %{optional(Types.env()) => String.t()}
  def api_urls, do: env_urls(&Types.api_url/1)

  @spec history_sync_urls() :: %{optional(Types.env()) => String.t()}
  def history_sync_urls, do: env_urls(&Types.history_sync_url/1)

  @spec metadata_field_name(Types.metadata_field()) :: String.t()
  def metadata_field_name(field), do: Types.metadata_field_name(field)

  @spec metadata_field_from_name(String.t()) ::
          {:ok, Types.metadata_field()} | {:error, Error.t()}
  def metadata_field_from_name(name), do: Types.metadata_field_from_name(name)

  defp env_urls(resolver) do
    for env <- @envs, into: %{}, do: {env, resolver.(env)}
  end
end

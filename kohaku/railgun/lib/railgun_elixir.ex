defmodule RailgunElixir do
  @moduledoc """
  Main entry point for the Railgun Elixir package.
  """

  alias KohakuPlugins.Asset
  alias RailgunElixir.{ChainConfig, Error, Native, Runtime}

  @spec start_runtime(keyword()) :: Supervisor.on_start()
  def start_runtime(opts), do: Runtime.start_link(opts)

  @spec runtime(atom()) :: Runtime.t()
  def runtime(name), do: Runtime.new(name)

  @spec chain_config(Runtime.t() | atom(), non_neg_integer()) ::
          {:ok, ChainConfig.t()} | {:error, Error.t()}
  def chain_config(runtime \\ __MODULE__, chain_id) when is_integer(chain_id) and chain_id >= 0 do
    with {:ok, %{"chain" => chain}} <-
           Native.request(Runtime.new(runtime), "chain_config", %{chain_id: chain_id}) do
      {:ok, ChainConfig.from_native(chain)}
    end
  end

  @spec chain_config_mainnet(Runtime.t() | atom()) :: {:ok, ChainConfig.t()} | {:error, Error.t()}
  def chain_config_mainnet(runtime \\ __MODULE__) do
    with {:ok, %{"chain" => chain}} <-
           Native.request(Runtime.new(runtime), "chain_config_mainnet") do
      {:ok, ChainConfig.from_native(chain)}
    end
  end

  @spec chain_config_sepolia(Runtime.t() | atom()) :: {:ok, ChainConfig.t()} | {:error, Error.t()}
  def chain_config_sepolia(runtime \\ __MODULE__) do
    with {:ok, %{"chain" => chain}} <-
           Native.request(Runtime.new(runtime), "chain_config_sepolia") do
      {:ok, ChainConfig.from_native(chain)}
    end
  end

  @spec erc20(String.t()) :: {:ok, Asset.t()} | {:error, Error.t()}
  def erc20(address) do
    case Asset.erc20(address) do
      {:ok, asset} -> {:ok, asset}
      {:error, error} -> {:error, Error.from(error)}
    end
  end

  @spec health(Runtime.t() | atom()) :: :ok | {:error, Error.t()}
  def health(runtime \\ __MODULE__) do
    with {:ok, %{"status" => "ok"}} <- Native.request(Runtime.new(runtime), "health") do
      :ok
    end
  end
end

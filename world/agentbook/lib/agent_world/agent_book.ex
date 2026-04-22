defmodule AgentWorld.AgentBook do
  @moduledoc false

  alias AgentWorld.Error
  alias AgentWorld.Internal.ABI
  alias AgentWorld.Internal.RPC
  alias AgentWorld.Networks

  @spec resolve_network(String.t(), map() | keyword()) :: {:ok, map()} | {:error, Error.t()}
  def resolve_network(network, opts \\ %{}), do: Networks.resolve(network, opts)

  @spec lookup_human(String.t(), String.t(), map() | keyword()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def lookup_human(agent_address, network, opts \\ %{}) do
    with {:ok, normalized_address} <- normalize_address(agent_address),
         {:ok, network_config} <- resolve_network(network, opts),
         {:ok, rpc_url} <- required_rpc_url(network_config),
         rpc <- rpc_module(opts),
         {:ok, data} <- ABI.encode_call("lookupHuman(address)", [{:address, normalized_address}]),
         {:ok, result} <- rpc.eth_call(rpc_url, network_config.contract_address, data),
         {:ok, human_id} <- ABI.decode_uint256(result) do
      {:ok, if(human_id == 0, do: nil, else: "0x" <> Integer.to_string(human_id, 16))}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new(reason)}
    end
  end

  defp required_rpc_url(%{id: network, rpc_url: rpc_url}) when is_binary(rpc_url) do
    trimmed = String.trim(rpc_url)

    if trimmed == "",
      do: {:error, Error.new({:missing_network_rpc, network})},
      else: {:ok, trimmed}
  end

  defp required_rpc_url(%{id: network}),
    do: {:error, Error.new({:missing_network_rpc, network})}

  defp normalize_address("0x" <> rest = address) when byte_size(rest) == 40 do
    if Regex.match?(~r/\A[0-9a-fA-F]{40}\z/, rest) do
      {:ok, String.downcase(address)}
    else
      {:error, Error.new({:invalid_address, address})}
    end
  end

  defp normalize_address(value), do: {:error, Error.new({:invalid_address, value})}

  defp rpc_module(opts) when is_list(opts), do: Keyword.get(opts, :rpc_module, RPC)

  defp rpc_module(opts) when is_map(opts),
    do: Map.get(opts, :rpc_module) || Map.get(opts, "rpc_module") || RPC

  defp rpc_module(_opts), do: RPC
end

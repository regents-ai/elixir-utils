defmodule AgentEns.Tx do
  @moduledoc """
  Unsigned transaction builders for ENS and ERC-8004 linking flows.
  """

  alias AgentEns.Error
  alias AgentEns.Internal.ABI
  alias AgentEns.Networks
  alias AgentEns.Normalize
  alias AgentEns.RecordKey
  alias AgentEns.TxRequest
  alias AgentEns.Verify

  @spec build_set_text_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_text_tx(params) when is_map(params) do
    with {:ok, ens_name} <- required(params, :ens_name),
         {:ok, chain_id} <- required_integer(params, :chain_id),
         {:ok, registry_address} <- required(params, :registry_address),
         {:ok, agent_id} <- required_agent_id(params),
         {:ok, resolver} <- required(params, :resolver_address),
         {:ok, value} <- optional(params, :value, "1"),
         {:ok, normalized_name} <- Normalize.normalize(ens_name),
         {:ok, node} <- Verify.namehash(normalized_name),
         {:ok, key} <- build_record_key(chain_id, registry_address, agent_id),
         {:ok, data} <-
           ABI.encode_call(
             "setText(bytes32,string,string)",
             [{:bytes32, node}, {:string, key}, {:string, value}]
           ) do
      {:ok,
       %TxRequest{
         to: String.downcase(resolver),
         data: data,
         value: 0,
         chain_id: chain_id,
         description: "Set ENSIP-25 verification text record on #{normalized_name}"
       }}
    end
  end

  @spec build_set_agent_uri_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_agent_uri_tx(params) when is_map(params) do
    with {:ok, chain_id} <- required_integer(params, :chain_id),
         {:ok, registry_address} <- required(params, :registry_address),
         {:ok, agent_id} <- required_integer(params, :agent_id),
         {:ok, new_uri} <- required(params, :new_uri),
         {:ok, data} <-
           ABI.encode_call(
             "setAgentURI(uint256,string)",
             [{:uint256, agent_id}, {:string, new_uri}]
           ) do
      {:ok,
       %TxRequest{
         to: String.downcase(registry_address),
         data: data,
         value: 0,
         chain_id: chain_id,
         description: "Update ERC-8004 registration URI for agent #{agent_id}"
       }}
    end
  end

  @spec build_reverse_set_name_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_reverse_set_name_tx(params) when is_map(params) do
    with {:ok, chain_id} <- required_integer(params, :chain_id),
         {:ok, ens_name} <- required(params, :ens_name),
         {:ok, normalized_name} <- Normalize.normalize(ens_name),
         {:ok, reverse_registrar} <- reverse_registrar(params, chain_id),
         {:ok, data} <- ABI.encode_call("setName(string)", [{:string, normalized_name}]) do
      {:ok,
       %TxRequest{
         to: reverse_registrar,
         data: data,
         value: 0,
         chain_id: chain_id,
         description: "Set reverse ENS primary name to #{normalized_name}"
       }}
    end
  end

  defp build_record_key(chain_id, registry_address, agent_id) when is_integer(agent_id) do
    RecordKey.evm_record_key(chain_id, registry_address, agent_id)
  end

  defp build_record_key(chain_id, registry_address, agent_id) when is_binary(agent_id) do
    with {:ok, interop} <- AgentEns.ERC7930.evm(chain_id, registry_address) do
      RecordKey.record_key(interop, agent_id)
    end
  end

  defp build_record_key(_chain_id, _registry_address, agent_id) do
    {:error, Error.new({:invalid_agent_id_type, agent_id})}
  end

  defp required(params, key) do
    case Map.get(params, key) || Map.get(params, Atom.to_string(key)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, Error.new({:missing_required_input, "#{key}: #{inspect(value)}"})}
    end
  end

  defp required_integer(params, key) do
    case Map.get(params, key) || Map.get(params, Atom.to_string(key)) do
      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {parsed, ""} when parsed >= 0 -> {:ok, parsed}
          _ -> {:error, Error.new({:invalid_argument, Atom.to_string(key), value})}
        end

      value ->
        {:error, Error.new({:missing_required_input, "#{key}: #{inspect(value)}"})}
    end
  end

  defp required_agent_id(params) do
    case Map.get(params, :agent_id) || Map.get(params, "agent_id") do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, Error.new({:missing_required_input, "#{:agent_id}: #{inspect(value)}"})}
    end
  end

  defp optional(params, key, default) do
    case Map.get(params, key) || Map.get(params, Atom.to_string(key)) do
      nil -> {:ok, default}
      "" -> {:ok, default}
      value when is_binary(value) -> {:ok, value}
      value -> {:error, Error.new({:invalid_argument, Atom.to_string(key), value})}
    end
  end

  defp reverse_registrar(params, chain_id) do
    case Map.get(params, :reverse_registrar) || Map.get(params, "reverse_registrar") do
      value when is_binary(value) and value != "" ->
        {:ok, String.downcase(value)}

      _ ->
        case Networks.get(chain_id) do
          %{reverse_registrar: value} when is_binary(value) and value != "" ->
            {:ok, String.downcase(value)}

          _ ->
            {:error, Error.new({:unsupported_network, chain_id})}
        end
    end
  end
end

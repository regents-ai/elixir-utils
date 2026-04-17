defmodule AgentEns.Internal.Contract do
  @moduledoc false

  alias AgentEns.Error
  alias AgentEns.Internal.ABI

  @text_interface_id "0x4920eeb0"
  @extended_resolver_interface_id "0x9061b923"

  @spec fetch_resolver(module(), String.t(), String.t(), binary()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def fetch_resolver(rpc, rpc_url, ens_registry, node) do
    with {:ok, data} <- ABI.encode_call("resolver(bytes32)", [{:bytes32, node}]),
         {:ok, result} <- rpc.eth_call(rpc_url, ens_registry, data),
         {:ok, resolver} <- ABI.decode_address(result) do
      case resolver do
        "0x0000000000000000000000000000000000000000" -> {:ok, nil}
        value -> {:ok, String.downcase(value)}
      end
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_text_record(module(), String.t(), String.t() | nil, binary(), String.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_text_record(_rpc, _rpc_url, nil, _node, _key), do: {:ok, ""}

  def fetch_text_record(rpc, rpc_url, resolver, node, key) do
    with {:ok, data} <-
           ABI.encode_call("text(bytes32,string)", [{:bytes32, node}, {:string, key}]),
         {:ok, result} <- rpc.eth_call(rpc_url, resolver, data),
         {:ok, value} <- ABI.decode_string(result) do
      {:ok, value}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, {:rpc_error, _} = reason} ->
        {:error, Error.new({:resolver_call_failed, reason})}

      {:error, reason} ->
        {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_registry_owner(module(), String.t(), String.t(), binary()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_registry_owner(rpc, rpc_url, ens_registry, node) do
    with {:ok, data} <- ABI.encode_call("owner(bytes32)", [{:bytes32, node}]),
         {:ok, result} <- rpc.eth_call(rpc_url, ens_registry, data),
         {:ok, owner} <- ABI.decode_address(result) do
      {:ok, String.downcase(owner)}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_wrapped_owner(module(), String.t(), String.t(), binary()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_wrapped_owner(rpc, rpc_url, name_wrapper, node) do
    token_id = :binary.decode_unsigned(node)

    with {:ok, data} <- ABI.encode_call("ownerOf(uint256)", [{:uint256, token_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, name_wrapper, data),
         {:ok, owner} <- ABI.decode_address(result) do
      {:ok, String.downcase(owner)}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:wrapped_name_owner_lookup_failed, reason})}
    end
  end

  @spec supports_text_write?(module(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def supports_text_write?(rpc, rpc_url, resolver) do
    supports_interface?(rpc, rpc_url, resolver, @text_interface_id)
  end

  @spec supports_extended_resolver?(module(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def supports_extended_resolver?(rpc, rpc_url, resolver) do
    supports_interface?(rpc, rpc_url, resolver, @extended_resolver_interface_id)
  end

  @spec fetch_token_owner(module(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_token_owner(rpc, rpc_url, registry_address, agent_id) do
    with {:ok, data} <- ABI.encode_call("ownerOf(uint256)", [{:uint256, agent_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, registry_address, data),
         {:ok, owner} <- ABI.decode_address(result) do
      {:ok, String.downcase(owner)}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_token_uri(module(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_token_uri(rpc, rpc_url, registry_address, agent_id) do
    with {:ok, data} <- ABI.encode_call("tokenURI(uint256)", [{:uint256, agent_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, registry_address, data),
         {:ok, uri} <- ABI.decode_string(result) do
      {:ok, uri}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_token_approval(module(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_token_approval(rpc, rpc_url, registry_address, agent_id) do
    with {:ok, data} <- ABI.encode_call("getApproved(uint256)", [{:uint256, agent_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, registry_address, data),
         {:ok, approval} <- ABI.decode_address(result) do
      {:ok, String.downcase(approval)}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec approved_for_all?(module(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def approved_for_all?(rpc, rpc_url, registry_address, owner, operator) do
    with {:ok, data} <-
           ABI.encode_call(
             "isApprovedForAll(address,address)",
             [{:address, owner}, {:address, operator}]
           ),
         {:ok, result} <- rpc.eth_call(rpc_url, registry_address, data),
         {:ok, value} <- ABI.decode_bool(result) do
      {:ok, value}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  defp supports_interface?(rpc, rpc_url, contract, interface_id) do
    with {:ok, data} <- ABI.encode_call("supportsInterface(bytes4)", [{:bytes4, interface_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, contract, data),
         {:ok, supported?} <- ABI.decode_bool(result) do
      {:ok, supported?}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, {:rpc_error, _} = reason} -> {:error, Error.new({:resolver_call_failed, reason})}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end
end

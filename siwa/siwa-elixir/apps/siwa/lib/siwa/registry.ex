defmodule Siwa.Registry do
  @service_types ["web", "A2A", "MCP", "OASF", "ENS", "DID", "email"]
  @trust_models ["reputation", "crypto-economic", "tee-attestation"]
  @registry_addresses %{
    1 => "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
    8453 => "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
    84532 => "0x8004A818BFB912233c491871b3d84c89A494BD9e",
    11_155_111 => "0x8004a6090Cd10A7288092483047B097295Fb8847",
    59141 => "0x8004aa7C931bCE1233973a0C6A667f73F66282e7",
    80002 => "0x8004ad19E14B9e0654f73353e8a0B600D46C2898"
  }
  @reputation_addresses %{
    1 => "0x8004BAa17C55a88189AE136b182e5fdA19dE9b63",
    8453 => "0x8004BAa17C55a88189AE136b182e5fdA19dE9b63",
    84532 => "0x8004B663056A597Dffe9eCcC1965A193B7388713"
  }
  @rpc_endpoints %{
    1 => "https://cloudflare-eth.com",
    8453 => "https://mainnet.base.org",
    84532 => "https://sepolia.base.org",
    11_155_111 => "https://rpc.sepolia.org",
    59141 => "https://rpc.sepolia.linea.build",
    80002 => "https://rpc-amoy.polygon.technology"
  }

  def service_types, do: @service_types
  def trust_models, do: @trust_models
  def registry_addresses, do: @registry_addresses
  def reputation_addresses, do: @reputation_addresses
  def rpc_endpoints, do: @rpc_endpoints

  def get_registry_address(chain_id), do: Map.fetch(@registry_addresses, chain_id)
  def get_reputation_address(chain_id), do: Map.fetch(@reputation_addresses, chain_id)
  def get_rpc_endpoint(chain_id), do: Map.fetch(@rpc_endpoints, chain_id)

  def get_agent_registry_string(chain_id) do
    with {:ok, address} <- get_registry_address(chain_id) do
      {:ok, "eip155:#{chain_id}:#{address}"}
    end
  end

  def parse_agent_registry("eip155:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [chain_id, address] ->
        {:ok,
         %{
           namespace: "eip155",
           chain_id: String.to_integer(chain_id),
           address: String.downcase(address)
         }}

      _ ->
        {:error, :invalid_agent_registry}
    end
  rescue
    _ -> {:error, :invalid_agent_registry}
  end

  def parse_agent_registry(_), do: {:error, :invalid_agent_registry}

  def get_agent(agent_id, opts) do
    client = Keyword.fetch!(opts, :client)
    registry_address = Keyword.fetch!(opts, :registry_address)

    with {:ok, owner} <- client.owner_of(registry_address, agent_id, opts),
         {:ok, uri} <- client.token_uri(registry_address, agent_id, opts),
         {:ok, wallet} <- client.agent_wallet(registry_address, agent_id, opts),
         {:ok, metadata} <- maybe_fetch_metadata(uri, opts) do
      {:ok,
       %{
         agent_id: agent_id,
         owner: owner,
         uri: uri,
         agent_wallet: wallet,
         metadata: metadata
       }}
    end
  end

  def get_reputation(agent_id, opts) do
    client = Keyword.fetch!(opts, :client)
    reputation_registry = Keyword.fetch!(opts, :reputation_registry_address)
    client.reputation_summary(reputation_registry, agent_id, opts)
  end

  def encode_register_agent(opts) do
    chain_id = Keyword.fetch!(opts, :chain_id)
    agent_uri = Keyword.fetch!(opts, :agent_uri)

    with {:ok, registry_address} <- get_registry_address(chain_id) do
      {:ok,
       %{
         to: registry_address,
         data: abi_encode_register(agent_uri)
       }}
    end
  end

  def register_agent(opts) do
    with {:ok, tx} <- encode_register_agent(opts) do
      case {Keyword.get(opts, :tx_signer), Keyword.get(opts, :client)} do
        {nil, _} ->
          {:ok, %{encoded: tx}}

        {signer, client} ->
          with {:ok, signed} <- signer_module(signer).sign_transaction(signer, tx),
               {:ok, result} <- client.submit_registration(signed, opts) do
            {:ok, %{encoded: tx, signed: signed, result: result}}
          end
      end
    end
  end

  defp maybe_fetch_metadata(uri, opts) do
    if Keyword.get(opts, :fetch_metadata, true) do
      fetch_metadata(uri)
    else
      {:ok, nil}
    end
  end

  defp fetch_metadata("ipfs://" <> cid),
    do: fetch_metadata("https://gateway.pinata.cloud/ipfs/" <> cid)

  defp fetch_metadata("data:application/json;base64," <> encoded),
    do: encoded |> Base.decode64!() |> Jason.decode()

  defp fetch_metadata("http://" <> _ = uri), do: fetch_http(uri)
  defp fetch_metadata("https://" <> _ = uri), do: fetch_http(uri)
  defp fetch_metadata(_), do: {:ok, nil}

  defp fetch_http(uri) do
    case Req.get(url: uri, receive_timeout: 5_000, retry: false) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} when is_binary(body) -> Jason.decode(body)
      {:ok, %{status: status}} -> {:error, {:metadata_http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp signer_module(%module{}), do: module

  defp abi_encode_register(agent_uri) do
    selector =
      "register(string)"
      |> KeccakEx.hash_256()
      |> binary_part(0, 4)

    body = abi_encode_string(agent_uri)
    "0x" <> Base.encode16(selector <> body, case: :lower)
  end

  defp abi_encode_string(value) do
    data = value
    padding = rem(32 - rem(byte_size(data), 32), 32)

    <<32::unsigned-big-integer-size(256), byte_size(data)::unsigned-big-integer-size(256),
      data::binary, 0::size(padding * 8)>>
  end
end

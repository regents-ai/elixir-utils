defmodule AgentWorld.Registration do
  @moduledoc false

  import Bitwise

  alias AgentWorld.Error
  alias AgentWorld.Internal.ABI
  alias AgentWorld.Internal.RPC
  alias AgentWorld.Networks
  alias AgentWorld.TxRequest

  @register_signature "register(address,uint256,uint256,uint256,uint256[8])"

  @spec create_session(map()) :: {:ok, map()} | {:error, Error.t()}
  def create_session(attrs) when is_map(attrs) do
    with {:ok, agent_address} <- normalize_address(fetch(attrs, "agent_address")),
         {:ok, network} <- normalize_network(fetch(attrs, "network")),
         {:ok, network_config} <- Networks.resolve(network, attrs),
         {:ok, rpc_url} <- required_rpc_url(network_config),
         rpc <- rpc_module(attrs),
         {:ok, world_id} <- Networks.world_id_config(attrs),
         {:ok, nonce} <- next_nonce(agent_address, rpc, rpc_url, network_config.contract_address),
         {:ok, signal} <- signal(agent_address, nonce),
         {:ok, rp_context} <- sign_request(world_id, Map.get(attrs, "action") || world_id.action) do
      {:ok,
       %{
         session_id: session_id(),
         status: :pending,
         agent_address: agent_address,
         network: network,
         chain_id: network_config.chain_id,
         contract_address: network_config.contract_address,
         relay_url: network_config.relay_url,
         nonce: nonce,
         app_id: world_id.app_id,
         action: Map.get(attrs, "action") || world_id.action,
         rp_id: world_id.rp_id,
         signal: signal,
         rp_context: Map.put(rp_context, :rp_id, world_id.rp_id),
         connector_uri: nil,
         deep_link_uri: nil,
         proof_payload: nil,
         tx_request: nil,
         tx_hash: nil,
         human_id: nil,
         error_text: nil,
         expires_at: DateTime.from_unix!(rp_context.expires_at)
       }}
    end
  end

  @spec submit_proof(map(), map(), map() | keyword()) :: {:ok, map()} | {:error, Error.t()}
  def submit_proof(session, proof_payload, options \\ %{})
      when is_map(session) and is_map(proof_payload) do
    with {:ok, normalized_proof} <- normalize_proof_payload(proof_payload),
         {:ok, tx_request} <- build_register_tx(session, normalized_proof) do
      maybe_submit_registration(session, normalized_proof, tx_request, options)
    end
  end

  @spec register_transaction(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def register_transaction(tx_hash, session) when is_binary(tx_hash) and is_map(session) do
    with {:ok, normalized_hash} <- normalize_tx_hash(tx_hash),
         {:ok, network} <- normalize_network(fetch(session, :network)),
         {:ok, network_config} <- Networks.resolve(network, session),
         {:ok, rpc_url} <- required_rpc_url(network_config),
         rpc <- rpc_module(session),
         {:ok, receipt} <- rpc.tx_receipt(rpc_url, normalized_hash) do
      case receipt do
        nil ->
          {:error, {:transaction_pending, normalized_hash}}

        %{"status" => "0x1"} ->
          {:ok, %{status: :registered, tx_hash: normalized_hash}}

        %{"status" => "0x0"} ->
          {:error, Error.new({:registration_failed, "Registration transaction reverted onchain"})}

        %{} ->
          {:error, {:transaction_pending, normalized_hash}}

        other ->
          {:error, Error.new({:invalid_rpc_result, other})}
      end
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new(reason)}
    end
  end

  defp maybe_submit_registration(session, proof_payload, tx_request, options) do
    submission = submission_mode(options)
    relay_url = session |> fetch(:relay_url) |> normalize_optional_binary()

    cond do
      submission == :manual ->
        {:ok,
         %{
           status: :proof_ready,
           proof_payload: proof_payload,
           tx_request: tx_request,
           error_text: "Manual submission requested."
         }}

      is_binary(relay_url) and relay_url != "" ->
        case relay_register(relay_url, session, proof_payload) do
          {:ok, tx_hash} ->
            {:ok,
             %{
               status: :registered,
               proof_payload: proof_payload,
               tx_hash: tx_hash,
               error_text: nil
             }}

          {:error, _reason} ->
            {:ok,
             %{
               status: :proof_ready,
               proof_payload: proof_payload,
               tx_request: tx_request,
               error_text: "Relay unavailable. Send the register transaction from your wallet."
             }}
        end

      true ->
        {:ok,
         %{
           status: :proof_ready,
           proof_payload: proof_payload,
           tx_request: tx_request,
           error_text: "Relay unavailable. Send the register transaction from your wallet."
         }}
    end
  end

  defp relay_register(relay_url, session, proof_payload) do
    url = relay_url |> String.trim_trailing("/") |> Kernel.<>("/register")

    body = %{
      agent: fetch(session, :agent_address),
      root: proof_payload["merkle_root"],
      nonce: Integer.to_string(fetch(session, :nonce)),
      nullifierHash: proof_payload["nullifier_hash"],
      proof: proof_payload["proof"],
      contract: fetch(session, :contract_address)
    }

    case RPC.relay_post(url, body) do
      {:ok, %{"txHash" => tx_hash}} when is_binary(tx_hash) ->
        {:ok, tx_hash}

      {:ok, payload} ->
        {:error, Error.new({:relay_missing_tx_hash, payload})}

      {:error, reason} ->
        {:error, Error.new({:relay_failed, reason})}
    end
  end

  defp build_register_tx(session, proof_payload) do
    with {:ok, agent_address} <- normalize_address(fetch(session, :agent_address)),
         {:ok, root} <- uint256(fetch(proof_payload, "merkle_root")),
         {:ok, nonce} <- uint256(fetch(session, :nonce)),
         {:ok, nullifier_hash} <- uint256(fetch(proof_payload, "nullifier_hash")),
         {:ok, proof} <- proof_words(fetch(proof_payload, "proof")),
         {:ok, to} <- normalize_address(fetch(session, :contract_address)),
         {:ok, chain_id} <- normalize_chain_id(fetch(session, :chain_id)) do
      {:ok,
       %TxRequest{
         to: to,
         data:
           ABI.selector(@register_signature) <>
             (ABI.address_word(agent_address) |> ok!()) <>
             ABI.uint256_word(root) <>
             ABI.uint256_word(nonce) <>
             ABI.uint256_word(nullifier_hash) <> Enum.join(proof, ""),
         value: "0x0",
         chain_id: chain_id,
         description: "Register agent wallet in AgentBook"
       }}
    end
  end

  defp proof_words(proof) when is_list(proof) and length(proof) == 8 do
    proof
    |> Enum.map(&uint256_word/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, word}, {:ok, acc} -> {:cont, {:ok, acc ++ [word]}}
      {:error, error}, _acc -> {:halt, {:error, error}}
    end)
  end

  defp proof_words(_value),
    do: {:error, Error.new({:invalid_argument, "proof", "expected 8 proof values"})}

  defp uint256_word(value) do
    with {:ok, integer} <- uint256(value) do
      {:ok, ABI.uint256_word(integer)}
    end
  end

  defp next_nonce(agent_address, rpc, rpc_url, contract_address) do
    with {:ok, data} <- ABI.encode_call("getNextNonce(address)", [{:address, agent_address}]),
         {:ok, result} <- rpc.eth_call(rpc_url, contract_address, data),
         {:ok, nonce} <- ABI.decode_uint256(result) do
      {:ok, nonce}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new(reason)}
    end
  end

  defp signal(agent_address, nonce) do
    with {:ok, address_word} <- ABI.address_word(agent_address) do
      {:ok, "0x" <> address_word <> ABI.uint256_word(nonce)}
    end
  end

  defp sign_request(world_id, action) do
    with {:ok, signing_key} <- private_key(world_id.signing_key),
         {:ok, nonce_bytes} <- hash_to_field(:crypto.strong_rand_bytes(32)),
         created_at = System.os_time(:second),
         expires_at = created_at + world_id.ttl_seconds,
         message = rp_signature_message(nonce_bytes, created_at, expires_at, action),
         digest = personal_message_hash(message),
         {:ok, {signature, recovery_id}} <- ExSecp256k1.sign_compact(digest, signing_key) do
      {:ok,
       %{
         nonce: "0x" <> Base.encode16(nonce_bytes, case: :lower),
         created_at: created_at,
         expires_at: expires_at,
         signature: "0x" <> Base.encode16(signature <> <<recovery_id + 27>>, case: :lower)
       }}
    else
      _ -> {:error, Error.new({:registration_failed, "Could not sign World request"})}
    end
  end

  defp hash_to_field(input) do
    hash = KeccakEx.hash_256(input)
    <<value::unsigned-big-integer-size(256)>> = hash
    field_value = bsr(value, 8)
    {:ok, <<field_value::unsigned-big-integer-size(256)>>}
  end

  defp rp_signature_message(nonce_bytes, created_at, expires_at, action) do
    action_bytes =
      case normalize_optional_binary(action) do
        value when is_binary(value) and value != "" ->
          {:ok, bytes} = hash_to_field(:erlang.iolist_to_binary(value))
          bytes

        _ ->
          <<>>
      end

    <<1, nonce_bytes::binary-size(32), created_at::unsigned-big-integer-size(64),
      expires_at::unsigned-big-integer-size(64), action_bytes::binary>>
  end

  defp personal_message_hash(message) do
    ("\x19Ethereum Signed Message:\n#{byte_size(message)}" <> message)
    |> KeccakEx.hash_256()
  end

  defp normalize_proof_payload(payload) do
    with {:ok, merkle_root} <-
           canonical_uint256(
             payload["merkle_root"] || payload[:merkle_root] || payload["root"] || payload[:root]
           ),
         {:ok, nullifier_hash} <-
           canonical_uint256(
             payload["nullifier_hash"] || payload[:nullifier_hash] || payload["nullifierHash"] ||
               payload[:nullifierHash]
           ),
         {:ok, proof} <- canonical_proof(payload["proof"] || payload[:proof]) do
      {:ok,
       %{
         "merkle_root" => merkle_root,
         "nullifier_hash" => nullifier_hash,
         "proof" => proof
       }}
    end
  end

  defp canonical_proof(raw) when is_list(raw) and length(raw) == 8 do
    raw
    |> Enum.map(&canonical_uint256/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, acc ++ [value]}}
      {:error, error}, _acc -> {:halt, {:error, error}}
    end)
  end

  defp canonical_proof(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    cond do
      String.starts_with?(trimmed, "[") ->
        case Jason.decode(trimmed) do
          {:ok, list} -> canonical_proof(list)
          _ -> {:error, Error.new({:invalid_argument, "proof", "could not decode proof array"})}
        end

      String.starts_with?(trimmed, "0x") ->
        decode_static_proof_hex(trimmed)

      true ->
        {:error, Error.new({:invalid_argument, "proof", "unsupported proof format"})}
    end
  end

  defp canonical_proof(_value),
    do: {:error, Error.new({:invalid_argument, "proof", "proof is required"})}

  defp decode_static_proof_hex("0x" <> hex) when byte_size(hex) == 64 * 8 do
    chunks =
      hex
      |> String.downcase()
      |> String.codepoints()
      |> Enum.chunk_every(64)
      |> Enum.map(&Enum.join/1)
      |> Enum.map(&("0x" <> &1))

    canonical_proof(chunks)
  end

  defp decode_static_proof_hex(_value),
    do: {:error, Error.new({:invalid_argument, "proof", "proof must contain exactly 8 values"})}

  defp canonical_uint256(value) do
    with {:ok, integer} <- uint256(value) do
      {:ok, "0x" <> String.pad_leading(Integer.to_string(integer, 16), 64, "0")}
    end
  end

  defp uint256(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp uint256("0x" <> hex = value) do
    case Integer.parse(hex, 16) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> {:error, Error.new({:invalid_uint256, value})}
    end
  end

  defp uint256(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> {:error, Error.new({:invalid_uint256, value})}
    end
  end

  defp uint256(value), do: {:error, Error.new({:invalid_uint256, value})}

  defp normalize_address("0x" <> rest = address) when byte_size(rest) == 40 do
    if Regex.match?(~r/\A[0-9a-fA-F]{40}\z/, rest) do
      {:ok, String.downcase(address)}
    else
      {:error, Error.new({:invalid_address, address})}
    end
  end

  defp normalize_address(value), do: {:error, Error.new({:invalid_address, value})}

  defp normalize_network(value)
       when is_binary(value) and value in ["world", "base", "base-sepolia"],
       do: {:ok, value}

  defp normalize_network(value), do: {:error, Error.new({:invalid_network, value})}

  defp normalize_chain_id(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp normalize_chain_id(value), do: {:error, Error.new({:invalid_argument, "chain_id", value})}

  defp normalize_tx_hash("0x" <> rest = value) when byte_size(rest) == 64 do
    if Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, rest) do
      {:ok, String.downcase(value)}
    else
      {:error, Error.new({:invalid_tx_hash, value})}
    end
  end

  defp normalize_tx_hash(value), do: {:error, Error.new({:invalid_tx_hash, value})}

  defp private_key(value) when is_binary(value) do
    trimmed = value |> String.trim() |> String.trim_leading("0x")

    with true <- byte_size(trimmed) == 64,
         {:ok, key} <- Base.decode16(trimmed, case: :mixed) do
      {:ok, key}
    else
      _ -> {:error, Error.new({:missing_world_id_config, :signing_key})}
    end
  end

  defp private_key(_value), do: {:error, Error.new({:missing_world_id_config, :signing_key})}

  defp required_rpc_url(%{id: network, rpc_url: rpc_url}) when is_binary(rpc_url) do
    trimmed = String.trim(rpc_url)

    if trimmed == "",
      do: {:error, Error.new({:missing_network_rpc, network})},
      else: {:ok, trimmed}
  end

  defp required_rpc_url(%{id: network}),
    do: {:error, Error.new({:missing_network_rpc, network})}

  defp submission_mode(options) when is_list(options) do
    case Keyword.get(options, :submission, :auto) do
      :manual -> :manual
      _ -> :auto
    end
  end

  defp submission_mode(options) when is_map(options) do
    case Map.get(options, :submission) || Map.get(options, "submission") do
      :manual -> :manual
      "manual" -> :manual
      _ -> :auto
    end
  end

  defp submission_mode(_options), do: :auto

  defp fetch(map, key) when is_binary(key),
    do: Map.get(map, key) || Map.get(map, maybe_atom_key(key))

  defp fetch(map, key) when is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp maybe_atom_key(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp normalize_optional_binary(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_optional_binary(_value), do: nil

  defp session_id do
    "session_" <> Base.encode16(:crypto.strong_rand_bytes(64), case: :lower)
  end

  defp ok!({:ok, value}), do: value

  defp rpc_module(opts) when is_list(opts), do: Keyword.get(opts, :rpc_module, RPC)

  defp rpc_module(opts) when is_map(opts) do
    Map.get(opts, :rpc_module) || Map.get(opts, "rpc_module") || RPC
  end

  defp rpc_module(_opts), do: RPC
end

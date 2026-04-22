defmodule AgentWorld.Agentkit do
  @moduledoc false

  alias AgentWorld.Error
  alias AgentWorld.Internal.ABI
  alias AgentWorld.Internal.RPC

  @default_max_age_ms 300_000
  @erc1271_magic "0x1626ba7e"
  @eth_prefix "\x19Ethereum Signed Message:\n"

  @required_keys ~w(domain address uri version chainId type nonce issuedAt signature)a
  @optional_keys ~w(statement expirationTime notBefore requestId resources signatureScheme)a
  @allowed_types ~w(eip191 eip1271 ed25519)

  @spec parse_agentkit_header(String.t()) :: {:ok, map()} | {:error, Error.t()}
  def parse_agentkit_header(header) when is_binary(header) do
    with {:ok, decoded} <- decode_header(header),
         {:ok, raw_payload} <- Jason.decode(decoded),
         {:ok, payload} <- normalize_payload(raw_payload) do
      {:ok, payload}
    end
  end

  def parse_agentkit_header(_value),
    do:
      {:error,
       Error.new({:invalid_agentkit_header, "Invalid agentkit header: expected a string"})}

  @spec validate_agentkit_message(map(), String.t(), map() | keyword()) ::
          {:ok, %{valid: true}} | {:error, Error.t()}
  def validate_agentkit_message(payload, expected_resource_uri, opts \\ %{})

  def validate_agentkit_message(payload, expected_resource_uri, opts)
      when is_map(payload) and is_binary(expected_resource_uri) do
    with {:ok, expected_uri} <- parse_uri(expected_resource_uri, "Invalid protected resource URI"),
         :ok <- validate_domain(payload, expected_uri),
         :ok <- validate_message_uri(payload, expected_uri),
         :ok <- validate_issued_at(payload, opts),
         :ok <- validate_expiration(payload),
         :ok <- validate_not_before(payload) do
      {:ok, %{valid: true}}
    end
  end

  def validate_agentkit_message(_payload, _expected_resource_uri, _opts),
    do: {:error, Error.new({:invalid_agentkit_message, "Invalid AgentKit validation input"})}

  @spec verify_agentkit_signature(map(), map() | keyword()) ::
          {:ok, %{address: String.t(), valid: true}} | {:error, Error.t()}
  def verify_agentkit_signature(payload, opts \\ %{})

  def verify_agentkit_signature(payload, opts) when is_map(payload) do
    chain_id = Map.get(payload, :chainId, "")

    cond do
      String.starts_with?(chain_id, "eip155:") ->
        verify_evm_payload(payload, opts)

      String.starts_with?(chain_id, "solana:") ->
        {:error, Error.new({:unsupported_chain_namespace, chain_id})}

      true ->
        {:error, Error.new({:unsupported_chain_namespace, chain_id})}
    end
  end

  defp verify_evm_payload(payload, opts) do
    with {:ok, message} <- format_siwe_message(payload),
         {:ok, rpc_url} <- optional_rpc_url(opts),
         :ok <- verify_evm_signature(message, payload.address, payload.signature, rpc_url) do
      {:ok, %{valid: true, address: String.downcase(payload.address)}}
    end
  end

  defp verify_evm_signature(message, address, signature, rpc_url) do
    digest = personal_hash(message)
    normalized_address = String.downcase(address)

    case recover_address(digest, signature) do
      {:ok, recovered} when recovered == normalized_address ->
        :ok

      _ ->
        maybe_verify_erc1271(digest, address, signature, rpc_url)
    end
  end

  defp maybe_verify_erc1271(_digest, _address, _signature, nil) do
    {:error, Error.new({:invalid_signature, "Signature verification failed"})}
  end

  defp maybe_verify_erc1271(digest, address, signature, rpc_url) do
    with {:ok, signature_bytes} <- signature_bytes(signature),
         {:ok, data} <-
           ABI.encode_call("isValidSignature(bytes32,bytes)", [
             {:bytes32, digest},
             {:bytes, signature_bytes}
           ]),
         {:ok, result} <- RPC.eth_call(rpc_url, address, data),
         true <- String.starts_with?(String.downcase(result), @erc1271_magic) do
      :ok
    else
      false ->
        {:error, Error.new({:invalid_signature, "Signature verification failed"})}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.new(reason)}

      _ ->
        {:error, Error.new({:invalid_signature, "Signature verification failed"})}
    end
  end

  defp recover_address(digest, signature) do
    with {:ok, {compact, recovery_id}} <- compact_signature(signature),
         {:ok, public_key} <- ExSecp256k1.recover_compact(digest, compact, recovery_id),
         {:ok, uncompressed} <- uncompressed_public_key(public_key) do
      <<4, raw::binary-size(64)>> = uncompressed
      hash = KeccakEx.hash_256(raw)
      {:ok, "0x" <> Base.encode16(binary_part(hash, byte_size(hash) - 20, 20), case: :lower)}
    else
      _ -> {:error, Error.new({:invalid_signature, "Signature verification failed"})}
    end
  end

  defp compact_signature(signature) do
    with {:ok, bytes} <- signature_bytes(signature),
         <<compact::binary-size(64), v>> <- bytes,
         {:ok, recovery_id} <- recovery_id(v) do
      {:ok, {compact, recovery_id}}
    else
      _ -> {:error, Error.new({:invalid_signature, "Invalid EVM signature"})}
    end
  end

  defp signature_bytes("0x" <> hex) when byte_size(hex) == 130 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<_::binary-size(65)>> = bytes} -> {:ok, bytes}
      _ -> {:error, Error.new({:invalid_signature, "Invalid signature encoding"})}
    end
  end

  defp signature_bytes(value),
    do: {:error, Error.new({:invalid_signature, "Invalid signature encoding: #{inspect(value)}"})}

  defp recovery_id(v) when v in [0, 1], do: {:ok, v}
  defp recovery_id(v) when v in [27, 28], do: {:ok, v - 27}
  defp recovery_id(v) when v >= 35, do: {:ok, rem(v - 35, 2)}
  defp recovery_id(_value), do: {:error, Error.new({:invalid_signature, "Invalid recovery id"})}

  defp uncompressed_public_key(<<4, _::binary-size(64)>> = key), do: {:ok, key}

  defp uncompressed_public_key(key) do
    case ExSecp256k1.public_key_decompress(key) do
      {:ok, <<4, _::binary-size(64)>> = decompressed} -> {:ok, decompressed}
      _ -> {:error, Error.new({:invalid_signature, "Invalid public key"})}
    end
  end

  defp format_siwe_message(payload) do
    with {:ok, numeric_chain_id} <- extract_evm_chain_id(payload.chainId) do
      lines = [
        "#{payload.domain} wants you to sign in with your Ethereum account:",
        payload.address,
        ""
      ]

      lines =
        if is_binary(payload.statement) and payload.statement != "" do
          lines ++ [payload.statement, ""]
        else
          lines
        end

      lines =
        lines ++
          [
            "URI: #{payload.uri}",
            "Version: #{payload.version}",
            "Chain ID: #{numeric_chain_id}",
            "Nonce: #{payload.nonce}",
            "Issued At: #{payload.issuedAt}"
          ]

      lines =
        maybe_append(lines, payload.expirationTime, "Expiration Time")
        |> maybe_append(payload.notBefore, "Not Before")
        |> maybe_append(payload.requestId, "Request ID")
        |> maybe_append_resources(payload.resources)

      {:ok, Enum.join(lines, "\n")}
    end
  end

  defp maybe_append(lines, value, label) when is_binary(value) and value != "" do
    lines ++ ["#{label}: #{value}"]
  end

  defp maybe_append(lines, _value, _label), do: lines

  defp maybe_append_resources(lines, resources) when is_list(resources) and resources != [] do
    lines ++ ["Resources:" | Enum.map(resources, &"- #{&1}")]
  end

  defp maybe_append_resources(lines, _resources), do: lines

  defp extract_evm_chain_id("eip155:" <> value) do
    case Integer.parse(value) do
      {chain_id, ""} when chain_id >= 0 -> {:ok, chain_id}
      _ -> {:error, Error.new({:invalid_signature, "Invalid EVM chain id"})}
    end
  end

  defp extract_evm_chain_id(chain_id),
    do: {:error, Error.new({:unsupported_chain_namespace, chain_id})}

  defp optional_rpc_url(opts) when is_list(opts) do
    opts
    |> Keyword.get(:rpc_url)
    |> normalize_rpc_url()
  end

  defp optional_rpc_url(opts) when is_map(opts) do
    opts
    |> Map.get(:rpc_url) ||
      Map.get(opts, "rpc_url")
      |> normalize_rpc_url()
  end

  defp optional_rpc_url(_opts), do: {:ok, nil}

  defp normalize_rpc_url(nil), do: {:ok, nil}

  defp normalize_rpc_url(value) when is_binary(value) do
    trimmed = String.trim(value)
    {:ok, if(trimmed == "", do: nil, else: trimmed)}
  end

  defp normalize_rpc_url(_value), do: {:ok, nil}

  defp personal_hash(message) do
    ("#{@eth_prefix}#{byte_size(message)}" <> message)
    |> KeccakEx.hash_256()
  end

  defp validate_domain(payload, expected_uri) do
    expected_domain = expected_uri.host
    got_domain = Map.get(payload, :domain)

    if got_domain == expected_domain do
      :ok
    else
      {:error,
       Error.new(
         {:invalid_agentkit_message,
          ~s(Domain mismatch: expected "#{expected_domain}", got "#{got_domain}")}
       )}
    end
  end

  defp validate_message_uri(payload, expected_uri) do
    with {:ok, message_uri} <- parse_uri(payload.uri, ~s(Invalid URI: "#{payload.uri}")) do
      if message_uri.host == expected_uri.host do
        :ok
      else
        {:error,
         Error.new(
           {:invalid_agentkit_message,
            ~s(URI mismatch: expected host "#{expected_uri.host}", got "#{message_uri.host}")}
         )}
      end
    end
  end

  defp validate_issued_at(payload, opts) do
    max_age = max_age(opts)

    with {:ok, issued_at} <- parse_datetime(payload.issuedAt, "Invalid issuedAt timestamp") do
      now = DateTime.utc_now()
      age_ms = DateTime.diff(now, issued_at, :millisecond)

      cond do
        age_ms < 0 ->
          {:error, Error.new({:invalid_agentkit_message, "issuedAt is in the future"})}

        age_ms > max_age ->
          seconds = round(age_ms / 1000)
          limit = round(max_age / 1000)

          {:error,
           Error.new(
             {:invalid_agentkit_message, "Message too old: #{seconds}s exceeds #{limit}s limit"}
           )}

        true ->
          :ok
      end
    end
  end

  defp validate_expiration(payload) do
    case Map.get(payload, :expirationTime) do
      value when is_binary(value) and value != "" ->
        with {:ok, expiration} <- parse_datetime(value, "Invalid expirationTime timestamp") do
          if DateTime.compare(expiration, DateTime.utc_now()) == :gt do
            :ok
          else
            {:error, Error.new({:invalid_agentkit_message, "Message expired"})}
          end
        end

      _ ->
        :ok
    end
  end

  defp validate_not_before(payload) do
    case Map.get(payload, :notBefore) do
      value when is_binary(value) and value != "" ->
        with {:ok, not_before} <- parse_datetime(value, "Invalid notBefore timestamp") do
          if DateTime.compare(DateTime.utc_now(), not_before) in [:gt, :eq] do
            :ok
          else
            {:error,
             Error.new(
               {:invalid_agentkit_message, "Message not yet valid (notBefore is in the future)"}
             )}
          end
        end

      _ ->
        :ok
    end
  end

  defp max_age(opts) when is_list(opts) do
    case Keyword.get(opts, :maxAge) || Keyword.get(opts, :max_age) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_max_age_ms
    end
  end

  defp max_age(opts) when is_map(opts) do
    case Map.get(opts, :maxAge) || Map.get(opts, "maxAge") || Map.get(opts, :max_age) ||
           Map.get(opts, "max_age") do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_max_age_ms
    end
  end

  defp max_age(_opts), do: @default_max_age_ms

  defp parse_datetime(value, error_message) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, Error.new({:invalid_agentkit_message, error_message})}
    end
  end

  defp parse_uri(value, error_message) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
        {:ok, uri}

      _ ->
        {:error, Error.new({:invalid_agentkit_message, error_message})}
    end
  end

  defp decode_header(header) do
    case Base.decode64(header, padding: false) do
      {:ok, decoded} ->
        {:ok, decoded}

      :error ->
        {:error,
         Error.new({:invalid_agentkit_header, "Invalid agentkit header: not valid base64"})}
    end
  end

  defp normalize_payload(%{} = raw_payload) do
    payload =
      Enum.reduce(@required_keys ++ @optional_keys, %{}, fn key, acc ->
        case map_fetch(raw_payload, key) do
          {:ok, value} -> Map.put(acc, key, value)
          :error -> acc
        end
      end)

    with :ok <- ensure_required_keys(payload),
         :ok <- ensure_type(payload),
         :ok <- ensure_binary_fields(payload) do
      normalized =
        payload
        |> Map.take(@required_keys ++ @optional_keys)
        |> Map.update!(:address, &String.downcase/1)

      {:ok, normalized}
    end
  end

  defp normalize_payload(_raw_payload),
    do:
      {:error,
       Error.new({:invalid_agentkit_header, "Invalid agentkit header: not valid JSON object"})}

  defp ensure_required_keys(payload) do
    missing =
      Enum.reject(@required_keys, fn key ->
        match?(value when is_binary(value) and value != "", Map.get(payload, key))
      end)

    case missing do
      [] ->
        :ok

      keys ->
        {:error,
         Error.new(
           {:invalid_agentkit_header,
            "Invalid agentkit header: missing #{Enum.map_join(keys, ", ", &Atom.to_string/1)}"}
         )}
    end
  end

  defp ensure_type(payload) do
    if Map.get(payload, :type) in @allowed_types do
      :ok
    else
      {:error, Error.new({:invalid_agentkit_header, "Invalid agentkit header: unsupported type"})}
    end
  end

  defp ensure_binary_fields(payload) do
    if Enum.all?(@required_keys, &is_binary(Map.get(payload, &1))) and
         valid_resources?(Map.get(payload, :resources)) do
      :ok
    else
      {:error, Error.new({:invalid_agentkit_header, "Invalid agentkit header: malformed fields"})}
    end
  end

  defp valid_resources?(nil), do: true
  defp valid_resources?(resources) when is_list(resources), do: Enum.all?(resources, &is_binary/1)
  defp valid_resources?(_resources), do: false

  defp map_fetch(map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        Map.fetch(map, Atom.to_string(key))
    end
  end
end

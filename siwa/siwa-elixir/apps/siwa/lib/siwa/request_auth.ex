defmodule Siwa.RequestAuth do
  alias Siwa.{EvmPersonalSign, Nonce, Receipt}

  @default_expires_in_seconds 120
  @default_signature_tolerance_seconds 300
  @receipt_header "x-siwa-receipt"
  @signature_header "signature"
  @signature_input_header "signature-input"
  @signature_regex ~r/^sig1=:(?<payload>[A-Za-z0-9+\/=]+):$/
  @content_digest_regex ~r/^sha-256=:(?<payload>[A-Za-z0-9+\/=]+):$/
  @positive_int_regex ~r/^[1-9][0-9]*$/

  @required_headers ~w(
    x-siwa-receipt
    signature
    signature-input
    x-key-id
    x-timestamp
    x-agent-wallet-address
    x-agent-chain-id
    x-agent-registry-address
    x-agent-token-id
  )

  @base_components ~w(
    @method
    @path
    x-siwa-receipt
    x-key-id
    x-timestamp
    x-agent-wallet-address
    x-agent-chain-id
  )

  @signature_components @base_components ++
                          ~w(
                            x-agent-registry-address
                            x-agent-token-id
                            content-digest
                          )

  def sign_authenticated_request(request, receipt, signer, opts \\ []) do
    request = normalize_request(request)

    with :ok <- ensure_request_body(request),
         {:ok, receipt_payload} <- verify_receipt(receipt, opts),
         :ok <- ensure_current_receipt(receipt_payload),
         {:ok, created} <- created_unix_seconds(opts),
         {:ok, expires} <- expires_unix_seconds(created, opts),
         {:ok, unsigned_headers} <-
           unsigned_headers(request, receipt, receipt_payload, created),
         signature_input <-
           build_signature_input(%{
             covered_components:
               required_components_for_headers(
                 unsigned_headers,
                 request_body_digest(request.body)
               ),
             created: created,
             expires: expires,
             nonce: Keyword.get(opts, :nonce, "sig-nonce-#{Nonce.generate_nonce(16)}"),
             key_id: receipt_payload["key_id"]
           }),
         signing_message <-
           build_http_signing_message(
             request.method,
             request.path,
             Map.put(unsigned_headers, @signature_input_header, signature_input)
           ),
         {:ok, signature} <- signer_module(signer).sign_message(signer, signing_message),
         {:ok, signature_header} <- encode_signature_header(signature) do
      headers =
        request.headers
        |> Map.merge(unsigned_headers)
        |> Map.put(@signature_input_header, signature_input)
        |> Map.put(@signature_header, signature_header)

      {:ok, Map.put(request, :headers, headers)}
    end
  end

  def verify_authenticated_request(request, opts \\ []) do
    request = normalize_request(request)
    body_digest = request_body_digest(request.body)

    with :ok <- ensure_request_body(request),
         :ok <- ensure_required_headers(request.headers, body_digest),
         {:ok, parsed_signature_input} <-
           parse_signature_input(Map.fetch!(request.headers, @signature_input_header)),
         :ok <- ensure_signature_window(parsed_signature_input, request.headers, opts),
         :ok <-
           ensure_covered_components(
             parsed_signature_input.components,
             request.headers,
             body_digest
           ),
         {:ok, receipt_payload} <-
           verify_receipt(Map.fetch!(request.headers, @receipt_header), opts),
         :ok <- ensure_current_receipt(receipt_payload),
         :ok <- ensure_body_binding(request.headers, body_digest),
         :ok <- ensure_header_binding(request.headers, receipt_payload),
         {:ok, signature} <- decode_signature(Map.fetch!(request.headers, @signature_header)),
         signing_message <-
           build_http_signing_message(
             request.method,
             request.path,
             request.headers,
             parsed_signature_input
           ),
         :ok <- verify_wallet_signature(signing_message, signature, receipt_payload["sub"]),
         :ok <-
           consume_replay_window(
             receipt_payload["sub"],
             parsed_signature_input.nonce,
             request.method,
             request.path,
             body_digest,
             parsed_signature_input.expires,
             opts
           ) do
      {:ok,
       %{
         address: receipt_payload["sub"],
         claims: receipt_payload,
         covered_components: parsed_signature_input.components
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize_request(request) do
    path = request[:path] || request["path"] || "/"

    %{
      method: request[:method] || request["method"] || "GET",
      path: path,
      host: request[:host] || request["host"] || "localhost",
      body: request[:body] || request["body"],
      headers: lowercase_headers(request[:headers] || request["headers"] || %{})
    }
  end

  def content_digest_for_body(body) when is_binary(body) do
    digest =
      :crypto.hash(:sha256, body)
      |> Base.encode64()

    "sha-256=:#{digest}:"
  end

  def content_digest_for_body(_body), do: nil

  def required_headers(body) do
    body
    |> request_body_digest()
    |> required_headers_for_digest()
  end

  def required_covered_components(headers, body) when is_map(headers) do
    body_digest = request_body_digest(body)

    headers
    |> lowercase_headers()
    |> required_components_for_headers(body_digest)
  end

  defp unsigned_headers(request, receipt, receipt_payload, created) do
    body_digest = request_body_digest(request.body)

    headers =
      %{
        @receipt_header => receipt,
        "x-key-id" => receipt_payload["key_id"],
        "x-timestamp" => Integer.to_string(created),
        "x-agent-wallet-address" => receipt_payload["sub"],
        "x-agent-chain-id" => Integer.to_string(receipt_payload["chain_id"]),
        "x-agent-registry-address" => receipt_payload["registry_address"],
        "x-agent-token-id" => receipt_payload["token_id"]
      }

    {:ok,
     if(is_binary(body_digest),
       do: Map.put(headers, "content-digest", body_digest),
       else: headers
     )}
  end

  defp lowercase_headers(headers),
    do: Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)

  defp ensure_request_body(%{body: body}) when is_nil(body) or is_binary(body), do: :ok
  defp ensure_request_body(_request), do: {:error, :invalid_request_body}

  defp verify_receipt(receipt, opts) when is_binary(receipt) do
    with {:ok, audience} <- required_audience(opts),
         {:ok, payload} <- Receipt.verify(receipt, Keyword.put(opts, :audience, audience)) do
      {:ok, payload}
    else
      {:error, :audience_required} -> {:error, :receipt_audience_required}
      {:error, :receipt_binding_mismatch} -> {:error, :receipt_binding_mismatch}
      {:error, _reason} -> {:error, :invalid_receipt}
    end
  end

  defp verify_receipt(_receipt, _opts), do: {:error, :invalid_receipt}

  defp required_audience(opts) do
    case Keyword.get(opts, :audience) do
      audience when is_binary(audience) ->
        case String.trim(audience) do
          "" -> {:error, :audience_required}
          value -> {:ok, value}
        end

      _ ->
        {:error, :audience_required}
    end
  end

  defp ensure_current_receipt(%{
         "typ" => "siwa_receipt",
         "jti" => jti,
         "sub" => sub,
         "aud" => aud,
         "chain_id" => chain_id,
         "nonce" => nonce,
         "key_id" => key_id,
         "registry_address" => registry_address,
         "token_id" => token_id
       })
       when is_binary(jti) and is_binary(sub) and is_binary(aud) and is_integer(chain_id) and
              is_binary(nonce) and is_binary(key_id) and is_binary(registry_address) and
              is_binary(token_id),
       do: :ok

  defp ensure_current_receipt(_payload), do: {:error, :invalid_receipt}

  defp created_unix_seconds(opts) do
    opts
    |> Keyword.get_lazy(:created_at, fn -> DateTime.utc_now() end)
    |> unix_seconds()
  end

  defp expires_unix_seconds(created, opts) do
    expires =
      case Keyword.get(opts, :expires_at) do
        nil -> created + Keyword.get(opts, :expires_in_seconds, @default_expires_in_seconds)
        value -> value
      end

    with {:ok, expires} <- unix_seconds(expires),
         true <- expires > created do
      {:ok, expires}
    else
      _ -> {:error, :invalid_signature_window}
    end
  end

  defp unix_seconds(%DateTime{} = datetime), do: {:ok, DateTime.to_unix(datetime, :second)}

  defp unix_seconds(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp unix_seconds(_value), do: {:error, :invalid_signature_window}

  defp build_signature_input(input) do
    signature_params =
      "(#{Enum.map_join(input.covered_components, " ", &~s("#{&1}"))})" <>
        ";created=#{input.created}" <>
        ";expires=#{input.expires}" <>
        ~s(;nonce="#{input.nonce}") <>
        ~s(;keyid="#{input.key_id}")

    "sig1=#{signature_params}"
  end

  defp parse_signature_input(signature_input) when is_binary(signature_input) do
    with %{"components" => components_blob, "params" => params_blob} <-
           Regex.named_captures(
             ~r/^sig1=\((?<components>.+)\)(?<params>(?:;.+)*)$/,
             String.trim(signature_input)
           ),
         {:ok, components} <- parse_components(components_blob),
         {:ok, params} <- parse_signature_params(params_blob) do
      {:ok,
       %{
         components: components,
         created: params.created,
         expires: params.expires,
         nonce: params.nonce,
         key_id: params.key_id,
         signature_params:
           "(#{Enum.map_join(components, " ", &~s("#{&1}"))})" <>
             ";created=#{params.created}" <>
             ";expires=#{params.expires}" <>
             ~s(;nonce="#{params.nonce}") <>
             if(params.key_id, do: ~s(;keyid="#{params.key_id}"), else: "")
       }}
    else
      _ -> {:error, :invalid_signature_input}
    end
  end

  defp parse_signature_input(_value), do: {:error, :invalid_signature_input}

  defp parse_components(blob) do
    case(
      blob
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reduce_while([], &reduce_signature_component/2)
    ) do
      {:error, reason} -> {:error, reason}
      components -> {:ok, Enum.reverse(components)}
    end
  end

  defp reduce_signature_component(token, components) do
    with true <- String.starts_with?(token, "\"") and String.ends_with?(token, "\""),
         component <- token |> String.trim_leading("\"") |> String.trim_trailing("\""),
         true <- component in @signature_components,
         false <- component in components do
      {:cont, [component | components]}
    else
      _ -> {:halt, {:error, :invalid_signature_input}}
    end
  end

  defp parse_signature_params(blob) do
    case(
      blob
      |> String.split(";", trim: true)
      |> Enum.reduce_while(%{}, &reduce_signature_param/2)
    ) do
      {:error, reason} ->
        {:error, reason}

      entries ->
        with {:ok, created} <- parse_positive_integer(entries["created"]),
             {:ok, expires} <- parse_positive_integer(entries["expires"]),
             {:ok, nonce} <- required_value(entries["nonce"]),
             {:ok, key_id} <- required_value(entries["keyid"]),
             true <- expires > created do
          {:ok,
           %{
             created: created,
             expires: expires,
             nonce: nonce,
             key_id: key_id
           }}
        else
          _ -> {:error, :invalid_signature_input}
        end
    end
  end

  defp reduce_signature_param(entry, acc) do
    case String.split(entry, "=", parts: 2) do
      [key, value] ->
        if Map.has_key?(acc, key) do
          {:halt, {:error, :invalid_signature_input}}
        else
          {:cont, Map.put(acc, key, String.trim(value, "\""))}
        end

      _ ->
        {:halt, {:error, :invalid_signature_input}}
    end
  end

  defp ensure_required_headers(headers, body_digest) do
    missing =
      required_headers_for_digest(body_digest)
      |> Enum.reject(&Map.has_key?(headers, &1))

    if missing == [], do: :ok, else: {:error, :missing_signed_headers}
  end

  defp required_headers_for_digest(body_digest) when is_binary(body_digest),
    do: @required_headers ++ ["content-digest"]

  defp required_headers_for_digest(_body_digest), do: @required_headers

  defp ensure_signature_window(parsed_signature_input, headers, opts) do
    now =
      opts
      |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end)
      |> DateTime.to_unix(:second)

    tolerance_seconds =
      Keyword.get(opts, :signature_tolerance_seconds, @default_signature_tolerance_seconds)

    with {:ok, header_timestamp} <- parse_positive_integer(Map.get(headers, "x-timestamp")) do
      cond do
        header_timestamp != parsed_signature_input.created ->
          {:error, :timestamp_mismatch}

        parsed_signature_input.key_id != Map.get(headers, "x-key-id") ->
          {:error, :signature_key_id_mismatch}

        parsed_signature_input.created > now + tolerance_seconds ->
          {:error, :request_not_yet_valid}

        parsed_signature_input.created < now - tolerance_seconds ->
          {:error, :request_too_old}

        parsed_signature_input.expires < now ->
          {:error, :request_expired}

        true ->
          :ok
      end
    else
      _ -> {:error, :invalid_timestamp}
    end
  end

  defp ensure_covered_components(components, headers, body_digest) do
    allowed = required_components_for_headers(headers, body_digest)
    missing = Enum.reject(allowed, &(&1 in components))
    extras = Enum.reject(components, &(&1 in allowed))

    cond do
      missing != [] -> {:error, :missing_covered_components}
      extras != [] -> {:error, :invalid_covered_components}
      true -> :ok
    end
  end

  defp required_components_for_headers(headers, body_digest) do
    @base_components
    |> maybe_append_content_digest(headers, body_digest)
    |> Kernel.++(["x-agent-registry-address", "x-agent-token-id"])
  end

  defp maybe_append_content_digest(components, headers, body_digest) do
    if is_binary(body_digest) or Map.has_key?(headers, "content-digest") do
      components ++ ["content-digest"]
    else
      components
    end
  end

  defp ensure_body_binding(headers, nil) do
    if Map.has_key?(headers, "content-digest") do
      {:error, :request_body_required}
    else
      :ok
    end
  end

  defp ensure_body_binding(headers, body_digest) do
    with content_digest when is_binary(content_digest) <- Map.get(headers, "content-digest"),
         true <- content_digest == body_digest,
         %{"payload" => payload} <- Regex.named_captures(@content_digest_regex, content_digest),
         {:ok, _decoded} <- Base.decode64(payload) do
      :ok
    else
      nil -> {:error, :missing_content_digest}
      false -> {:error, :content_digest_mismatch}
      _ -> {:error, :invalid_content_digest}
    end
  end

  defp ensure_header_binding(headers, receipt_payload) do
    [
      fn -> ensure_address_claim_binding(headers, receipt_payload, "x-key-id", "key_id") end,
      fn ->
        ensure_address_claim_binding(headers, receipt_payload, "x-agent-wallet-address", "sub")
      end,
      fn -> ensure_chain_binding(headers, receipt_payload) end,
      fn ->
        ensure_address_claim_binding(
          headers,
          receipt_payload,
          "x-agent-registry-address",
          "registry_address"
        )
      end,
      fn -> ensure_claim_binding(headers, receipt_payload, "x-agent-token-id", "token_id") end
    ]
    |> Enum.reduce_while(:ok, fn check, :ok ->
      case check.() do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_claim_binding(headers, claims, header_name, claim_name) do
    if Map.get(headers, header_name) == claims[claim_name],
      do: :ok,
      else: {:error, :receipt_binding_mismatch}
  end

  defp ensure_address_claim_binding(headers, claims, header_name, claim_name) do
    if normalize_address(Map.get(headers, header_name)) == normalize_address(claims[claim_name]),
      do: :ok,
      else: {:error, :receipt_binding_mismatch}
  end

  defp ensure_chain_binding(headers, claims) do
    with {:ok, chain_id} <- parse_positive_integer(Map.get(headers, "x-agent-chain-id")),
         true <- chain_id == claims["chain_id"] do
      :ok
    else
      _ -> {:error, :chain_binding_mismatch}
    end
  end

  defp decode_signature(signature_header) when is_binary(signature_header) do
    with %{"payload" => payload} <-
           Regex.named_captures(@signature_regex, String.trim(signature_header)),
         {:ok, <<_::binary-size(65)>> = bytes} <- Base.decode64(payload) do
      {:ok, "0x" <> Base.encode16(bytes, case: :lower)}
    else
      _ -> {:error, :invalid_signature_header}
    end
  end

  defp decode_signature(_signature_header), do: {:error, :invalid_signature_header}

  defp encode_signature_header("0x" <> hex) when byte_size(hex) == 130 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<_::binary-size(65)>> = bytes} -> {:ok, "sig1=:#{Base.encode64(bytes)}:"}
      _ -> {:error, :invalid_signature}
    end
  end

  defp encode_signature_header(_signature), do: {:error, :invalid_signature}

  defp build_http_signing_message(method, request_path, headers, parsed_signature_input) do
    parsed_signature_input.components
    |> Enum.map(fn component ->
      value =
        case component do
          "@method" -> String.downcase(method)
          "@path" -> request_path
          header_name -> Map.fetch!(headers, header_name)
        end

      ~s("#{component}": #{value})
    end)
    |> Kernel.++([~s("@signature-params": #{parsed_signature_input.signature_params})])
    |> Enum.join("\n")
  end

  defp build_http_signing_message(method, request_path, headers) do
    with {:ok, parsed_signature_input} <-
           parse_signature_input(Map.fetch!(headers, @signature_input_header)) do
      build_http_signing_message(method, request_path, headers, parsed_signature_input)
    end
  end

  defp consume_replay_window(
         wallet_address,
         nonce,
         method,
         request_path,
         body_digest,
         expires,
         opts
       ) do
    now =
      opts
      |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end)
      |> DateTime.to_unix(:second)

    replay_expires_at = max(now, expires)

    replay_key =
      Enum.join(
        [
          wallet_address,
          nonce,
          String.upcase(method),
          request_path,
          body_digest || ""
        ],
        "|"
      )

    case Keyword.get(opts, :replay_store) do
      nil ->
        Siwa.RequestAuth.ReplayStore.consume(replay_key, replay_expires_at)

      fun when is_function(fun, 2) ->
        fun.(replay_key, replay_expires_at)

      module when is_atom(module) ->
        module.consume(replay_key, replay_expires_at)
    end
  end

  defp request_body_digest(nil), do: nil
  defp request_body_digest(body) when is_binary(body), do: content_digest_for_body(body)

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    if Regex.match?(@positive_int_regex, String.trim(value)) do
      {:ok, String.to_integer(String.trim(value))}
    else
      {:error, :invalid}
    end
  end

  defp parse_positive_integer(_value), do: {:error, :invalid}

  defp required_value(nil), do: {:error, :missing}
  defp required_value(""), do: {:error, :missing}
  defp required_value(value), do: {:ok, value}

  defp normalize_address(value) when is_binary(value), do: String.downcase(value)
  defp normalize_address(_value), do: nil

  defp verify_wallet_signature(message, signature, address) do
    case EvmPersonalSign.verify_personal_signature(message, signature, address) do
      :ok -> :ok
      {:error, _reason} -> {:error, :signature_invalid}
    end
  end

  defp signer_module(%module{}), do: module
end

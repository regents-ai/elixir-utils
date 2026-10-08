defmodule Siwa.RequestAuth do
  @moduledoc """
  Signs and verifies agent requests under `Siwa.Contract`, which names every
  header, component and parameter used here.
  """

  alias Siwa.{Contract, Receipt, WalletSignature}

  @default_signature_tolerance_seconds 300
  @positive_int_regex ~r/^[1-9][0-9]*$/

  @label Contract.label()
  @receipt_header Contract.header_for("receipt")
  @key_id_header Contract.header_for("key_id")
  @timestamp_header Contract.header_for("created")
  @wallet_address_header Contract.header_for("wallet_address")
  @chain_id_header Contract.header_for("chain_id")
  @signature_header Contract.signature_header()
  @signature_input_header Contract.signature_input_header()
  @body_component Contract.body_component()
  @required_headers Contract.required_headers()
  @base_components Contract.component_names()
  @signature_components @base_components ++ [@body_component]

  def sign_authenticated_request(request, receipt, signer, opts \\ []) do
    request = normalize_request(request)

    with :ok <- ensure_request_body(request),
         {:ok, receipt_payload} <- verify_receipt(receipt, opts),
         :ok <- ensure_wallet_receipt(receipt_payload, opts),
         {:ok, created} <- created_unix_seconds(opts),
         {:ok, expires} <- expires_unix_seconds(created, opts),
         unsigned_headers <- unsigned_headers(request, receipt, receipt_payload, created),
         signature_input <-
           build_signature_input(
             required_components_for_headers(unsigned_headers, request_body_digest(request.body)),
             %{
               "created" => created,
               "expires" => expires,
               "nonce" => Keyword.get_lazy(opts, :nonce, &signature_nonce/0),
               "key_id" => receipt_payload["key_id"]
             }
           ),
         {:ok, signing_message} <-
           signing_message(%{
             request
             | headers: Map.put(unsigned_headers, @signature_input_header, signature_input)
           }),
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
         {:ok, receipt_payload} <-
           verify_receipt(Map.fetch!(request.headers, @receipt_header), opts),
         :ok <- ensure_wallet_receipt(receipt_payload, opts),
         {:ok, parsed_signature_input} <-
           parse_signature_input(Map.fetch!(request.headers, @signature_input_header)),
         :ok <- ensure_signature_window(parsed_signature_input, request.headers, opts),
         :ok <-
           ensure_covered_components(
             parsed_signature_input.components,
             request.headers,
             body_digest
           ),
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
         {:ok, verification_method} <-
           verify_wallet_signature(signing_message, signature, receipt_payload, opts),
         :ok <-
           consume_replay_window(
             receipt_payload,
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
         covered_components: parsed_signature_input.components,
         verification_method: verification_method
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The message a request's signature covers, read from its signature-input header."
  def signing_message(request) do
    request = normalize_request(request)

    with {:ok, parsed_signature_input} <-
           parse_signature_input(Map.get(request.headers, @signature_input_header)) do
      {:ok,
       build_http_signing_message(
         request.method,
         request.path,
         request.headers,
         parsed_signature_input
       )}
    end
  end

  def normalize_request(request) do
    path = request[:path] || request["path"] || "/"

    %{
      method: request[:method] || request["method"] || "GET",
      path: path,
      body: request[:body] || request["body"],
      headers: lowercase_headers(request[:headers] || request["headers"] || %{})
    }
  end

  def content_digest_for_body(body) when is_binary(body) do
    digest =
      :crypto.hash(:sha256, body)
      |> Base.encode64()

    "#{Contract.body_algorithm()}=:#{digest}:"
  end

  def content_digest_for_body(_body), do: nil

  def required_headers(body) do
    body
    |> request_body_digest()
    |> required_headers_for_digest()
  end

  def required_covered_components(headers, body) when is_map(headers) do
    headers
    |> lowercase_headers()
    |> required_components_for_headers(request_body_digest(body))
  end

  defp unsigned_headers(request, receipt, receipt_payload, created) do
    values = %{
      "receipt" => receipt,
      "key_id" => receipt_payload["key_id"],
      "created" => Integer.to_string(created),
      "wallet_address" => receipt_payload["sub"],
      "chain_id" => Integer.to_string(receipt_payload["chain_id"])
    }

    headers =
      Map.new(Contract.header_components(), fn {header, from} ->
        {header, Map.fetch!(values, from)}
      end)

    case request_body_digest(request.body) do
      nil -> headers
      body_digest -> Map.put(headers, @body_component, body_digest)
    end
  end

  defp signature_nonce do
    nonce = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    "sig-nonce-" <> binary_part(nonce, 0, 16)
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

  defp ensure_wallet_receipt(
         %{
           "typ" => "siwa_wallet_receipt",
           "verified" => "wallet_signature",
           "jti" => jti,
           "sub" => sub,
           "aud" => aud,
           "chain_id" => chain_id,
           "nonce" => nonce,
           "key_id" => key_id
         },
         opts
       )
       when is_binary(jti) and byte_size(jti) > 0 and is_binary(sub) and
              is_integer(chain_id) and chain_id > 0 and
              is_binary(aud) and byte_size(aud) > 0 and is_binary(nonce) and
              byte_size(nonce) > 0 and is_binary(key_id) do
    cond do
      not Regex.match?(~r/^0x[0-9a-fA-F]{40}$/, sub) or
          normalize_address(sub) != normalize_address(key_id) ->
        {:error, :invalid_receipt}

      aud not in Keyword.get(opts, :wallet_audiences, []) ->
        {:error, :wallet_principal_not_allowed}

      true ->
        :ok
    end
  end

  defp ensure_wallet_receipt(_payload, _opts), do: {:error, :invalid_receipt}

  defp created_unix_seconds(opts) do
    opts
    |> Keyword.get_lazy(:created_at, fn -> DateTime.utc_now() end)
    |> unix_seconds()
  end

  defp expires_unix_seconds(created, opts) do
    expires =
      case Keyword.get(opts, :expires_at) do
        nil -> created + Keyword.get(opts, :expires_in_seconds, Contract.lifetime_seconds())
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

  defp build_signature_input(components, values),
    do: "#{@label}=#{signature_params(components, values)}"

  # The parameters follow the contract's order; created and expires are bare
  # integers, the others quoted strings (RFC 9421).
  defp signature_params(components, values) do
    "(#{Enum.map_join(components, " ", &~s("#{&1}"))})" <>
      Enum.map_join(Contract.params(), fn {name, from} ->
        ";#{name}=#{param_value(from, Map.fetch!(values, from))}"
      end)
  end

  defp param_value(from, value) when from in ["created", "expires"], do: Integer.to_string(value)
  defp param_value(_from, value), do: ~s("#{value}")

  defp parse_signature_input(signature_input) when is_binary(signature_input) do
    with %{"components" => components_blob, "params" => params_blob} <-
           Regex.named_captures(
             ~r/^#{@label}=\((?<components>.+)\)(?<params>(?:;.+)*)$/,
             String.trim(signature_input)
           ),
         {:ok, components} <- parse_components(components_blob),
         {:ok, params} <- parse_signature_params(params_blob) do
      {:ok,
       %{
         components: components,
         created: params["created"],
         expires: params["expires"],
         nonce: params["nonce"],
         key_id: params["key_id"],
         signature_params: signature_params(components, params)
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
        param = &entries[Contract.param_name(&1)]

        with {:ok, created} <- parse_positive_integer(param.("created")),
             {:ok, expires} <- parse_positive_integer(param.("expires")),
             {:ok, nonce} <- required_value(param.("nonce")),
             {:ok, key_id} <- required_value(param.("key_id")),
             true <- expires > created do
          {:ok,
           %{"created" => created, "expires" => expires, "nonce" => nonce, "key_id" => key_id}}
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
      body_digest
      |> required_headers_for_digest()
      |> Enum.reject(&Map.has_key?(headers, &1))

    if missing == [], do: :ok, else: {:error, :missing_signed_headers}
  end

  defp required_headers_for_digest(nil), do: @required_headers
  defp required_headers_for_digest(_body_digest), do: @required_headers ++ [@body_component]

  defp ensure_signature_window(parsed_signature_input, headers, opts) do
    now =
      opts
      |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end)
      |> DateTime.to_unix(:second)

    tolerance_seconds =
      Keyword.get(opts, :signature_tolerance_seconds, @default_signature_tolerance_seconds)

    with {:ok, header_timestamp} <- parse_positive_integer(Map.get(headers, @timestamp_header)) do
      cond do
        header_timestamp != parsed_signature_input.created ->
          {:error, :timestamp_mismatch}

        parsed_signature_input.key_id != Map.get(headers, @key_id_header) ->
          {:error, :signature_key_id_mismatch}

        parsed_signature_input.created > now + tolerance_seconds ->
          {:error, :request_not_yet_valid}

        parsed_signature_input.created < now - tolerance_seconds ->
          {:error, :request_too_old}

        parsed_signature_input.expires <= now ->
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
    if is_binary(body_digest) or Map.has_key?(headers, @body_component) do
      @signature_components
    else
      @base_components
    end
  end

  defp ensure_body_binding(headers, nil) do
    if Map.has_key?(headers, @body_component) do
      {:error, :request_body_required}
    else
      :ok
    end
  end

  defp ensure_body_binding(headers, body_digest) do
    with content_digest when is_binary(content_digest) <- Map.get(headers, @body_component),
         true <- content_digest == body_digest,
         %{"payload" => payload} <-
           Regex.named_captures(
             ~r/^#{Contract.body_algorithm()}=:(?<payload>[A-Za-z0-9+\/=]+):$/,
             content_digest
           ),
         {:ok, _decoded} <- Base.decode64(payload) do
      :ok
    else
      nil -> {:error, :missing_content_digest}
      false -> {:error, :content_digest_mismatch}
      _ -> {:error, :invalid_content_digest}
    end
  end

  defp ensure_header_binding(headers, receipt_payload) do
    checks = [
      fn -> ensure_address_claim_binding(headers, receipt_payload, @key_id_header, "key_id") end,
      fn ->
        ensure_address_claim_binding(headers, receipt_payload, @wallet_address_header, "sub")
      end,
      fn -> ensure_chain_binding(headers, receipt_payload) end
    ]

    Enum.reduce_while(checks, :ok, fn check, :ok ->
      case check.() do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_address_claim_binding(headers, claims, header_name, claim_name) do
    if normalize_address(Map.get(headers, header_name)) == normalize_address(claims[claim_name]),
      do: :ok,
      else: {:error, :receipt_binding_mismatch}
  end

  defp ensure_chain_binding(headers, claims) do
    with {:ok, chain_id} <- parse_positive_integer(Map.get(headers, @chain_id_header)),
         true <- chain_id == claims["chain_id"] do
      :ok
    else
      _ -> {:error, :chain_binding_mismatch}
    end
  end

  defp decode_signature(signature_header) when is_binary(signature_header) do
    with %{"payload" => payload} <-
           Regex.named_captures(
             ~r/^#{@label}=:(?<payload>[A-Za-z0-9+\/=]+):$/,
             String.trim(signature_header)
           ),
         {:ok, bytes} <- Base.decode64(payload),
         true <- byte_size(bytes) in 1..WalletSignature.max_bytes() do
      {:ok, "0x" <> Base.encode16(bytes, case: :lower)}
    else
      _ -> {:error, :invalid_signature_header}
    end
  end

  defp decode_signature(_signature_header), do: {:error, :invalid_signature_header}

  defp encode_signature_header("0x" <> hex) do
    with {:ok, bytes} <- Base.decode16(hex, case: :mixed),
         true <- byte_size(bytes) in 1..WalletSignature.max_bytes() do
      {:ok, "#{@label}=:#{Base.encode64(bytes)}:"}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp encode_signature_header(_signature), do: {:error, :invalid_signature}

  defp build_http_signing_message(method, request_path, headers, parsed_signature_input) do
    parsed_signature_input.components
    |> Enum.map(fn component ->
      value =
        case Contract.source(component) do
          "method" -> String.downcase(method)
          "path" -> request_path
          _header -> Map.fetch!(headers, component)
        end

      ~s("#{component}": #{value})
    end)
    |> Kernel.++([~s("@signature-params": #{parsed_signature_input.signature_params})])
    |> Enum.join("\n")
  end

  defp consume_replay_window(
         receipt_payload,
         nonce,
         method,
         request_path,
         body_digest,
         expires,
         opts
       ) do
    replay_key =
      Jason.encode!([
        "wallet",
        normalize_address(receipt_payload["sub"]),
        receipt_payload["chain_id"],
        receipt_payload["aud"],
        nonce,
        String.upcase(method),
        request_path,
        body_digest || ""
      ])

    case Keyword.get(opts, :replay_store) do
      nil ->
        Siwa.RequestAuth.ReplayStore.consume(replay_key, expires)

      fun when is_function(fun, 2) ->
        fun.(replay_key, expires)

      module when is_atom(module) ->
        module.consume(replay_key, expires)
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

  # An ordinary wallet's signature is checked here; a smart wallet's is asked
  # of the receipt's chain, read as the `:chain_rpcs` opt says for that chain id
  # (`Siwa.WalletSignature.verify/4`).
  defp verify_wallet_signature(
         message,
         signature,
         %{"sub" => address, "chain_id" => chain_id},
         opts
       ) do
    rpc = opts |> Keyword.get(:chain_rpcs, %{}) |> Map.get(chain_id, [])

    case WalletSignature.verify(address, message, signature, rpc) do
      {:ok, method} -> {:ok, method}
      {:error, :signature_invalid} -> {:error, :signature_invalid}
      {:error, {:lookup_failed, _reason}} -> {:error, :signature_lookup_failed}
    end
  end

  defp signer_module(%module{}), do: module
end

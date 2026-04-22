defmodule Siwa.RequestAuth do
  alias Siwa.{Crypto, Receipt}

  @default_request_max_age_ms 2 * 60 * 1_000
  @default_clock_skew_ms 30 * 1_000
  @receipt_header "x-siwa-receipt"
  @auth_header "x-siwa-auth"
  @signature_header "x-siwa-signature"

  def sign_authenticated_request(request, receipt, signer, opts \\ []) do
    request = normalize_request(request)

    created_at =
      Keyword.get(opts, :created_at, DateTime.utc_now()) |> DateTime.to_unix(:millisecond)

    nonce = Keyword.get(opts, :nonce, Siwa.Nonce.generate_nonce(12))

    auth = %{
      method: request.method,
      path: request.path,
      host: request.host,
      query: request.query,
      body_hash: body_hash(request.body),
      created_at: created_at,
      nonce: nonce
    }

    payload = Jason.encode!(auth)

    with {:ok, signature} <- signer_module(signer).sign_raw_message(signer, payload) do
      headers =
        request.headers
        |> Map.put(@receipt_header, receipt)
        |> Map.put(@auth_header, Base.url_encode64(payload, padding: false))
        |> Map.put(@signature_header, Base.url_encode64(Jason.encode!(signature), padding: false))

      {:ok, Map.put(request, :headers, headers)}
    end
  end

  def verify_authenticated_request(request, opts \\ []) do
    request = normalize_request(request)
    replay_ttl_ms = Keyword.get(opts, :replay_ttl_ms, 5 * 60 * 1_000)

    now_ms =
      opts
      |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end)
      |> DateTime.to_unix(:millisecond)

    with {:ok, receipt} <- fetch_header(request, @receipt_header),
         {:ok, receipt_payload} <- Receipt.verify(receipt, opts),
         {:ok, auth_json, auth_payload} <- fetch_and_decode_with_json(request, @auth_header),
         {:ok, _signature_json, signature} <-
           fetch_and_decode_with_json(request, @signature_header),
         :ok <- ensure_request_matches(request, auth_payload),
         :ok <- ensure_request_freshness(auth_payload, now_ms, opts),
         {:ok, verified_signature} <- verify_signature(signature, auth_json, opts),
         :ok <- ensure_receipt_matches(receipt_payload, verified_signature),
         :ok <-
           Siwa.RequestAuth.ReplayStore.consume(
             replay_key(auth_payload, verified_signature),
             replay_ttl_ms
           ) do
      {:ok,
       %{address: verified_signature.address, auth: auth_payload, signature: verified_signature}}
    end
  end

  def normalize_request(request) do
    %{
      method: request[:method] || request["method"] || "GET",
      path: request[:path] || request["path"] || "/",
      host: request[:host] || request["host"] || "localhost",
      query: request[:query] || request["query"] || "",
      body: request[:body] || request["body"] || "",
      headers: lowercase_headers(request[:headers] || request["headers"] || %{})
    }
  end

  defp lowercase_headers(headers),
    do: Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)

  defp fetch_header(request, key) do
    case Map.fetch(request.headers, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_header, key}}
    end
  end

  defp fetch_and_decode_with_json(request, header) do
    with {:ok, encoded} <- fetch_header(request, header),
         {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, decoded} <- Jason.decode(json) do
      {:ok, json, decoded}
    else
      _ -> {:error, {:invalid_header, header}}
    end
  end

  defp ensure_request_matches(request, auth_payload) do
    cond do
      request.method != auth_payload["method"] -> {:error, :request_method_mismatch}
      request.path != auth_payload["path"] -> {:error, :request_path_mismatch}
      request.host != auth_payload["host"] -> {:error, :request_host_mismatch}
      request.query != auth_payload["query"] -> {:error, :request_query_mismatch}
      body_hash(request.body) != auth_payload["body_hash"] -> {:error, :request_body_mismatch}
      true -> :ok
    end
  end

  defp ensure_request_freshness(auth_payload, now_ms, opts) do
    max_age_ms = Keyword.get(opts, :request_max_age_ms, @default_request_max_age_ms)
    clock_skew_ms = Keyword.get(opts, :clock_skew_ms, @default_clock_skew_ms)

    with {:ok, created_at_ms} <- fetch_created_at_ms(auth_payload) do
      cond do
        created_at_ms > now_ms + clock_skew_ms ->
          {:error, :request_not_yet_valid}

        now_ms - created_at_ms > max_age_ms ->
          {:error, :request_too_old}

        true ->
          :ok
      end
    end
  end

  defp fetch_created_at_ms(%{"created_at" => created_at})
       when is_integer(created_at) and created_at >= 0,
       do: {:ok, created_at}

  defp fetch_created_at_ms(_auth_payload), do: {:error, :request_missing_timestamp}

  defp verify_signature(signature, payload, opts) do
    case Keyword.get(opts, :signature_validator) do
      nil -> Crypto.verify_raw(signature, payload)
      fun when is_function(fun, 2) -> fun.(signature, payload)
      module -> module.verify(signature, payload, opts)
    end
  end

  defp ensure_receipt_matches(receipt_payload, verified_signature) do
    receipt_address = receipt_payload["address"]
    signature_address = verified_signature.address || verified_signature[:address]

    if comparable_address(receipt_address) == comparable_address(signature_address) do
      :ok
    else
      {:error, :receipt_signer_mismatch}
    end
  end

  defp comparable_address(value) when is_binary(value), do: String.downcase(value)
  defp comparable_address(_value), do: nil

  defp replay_key(auth_payload, signature) do
    Enum.join(
      [
        auth_payload["method"],
        auth_payload["path"],
        to_string(auth_payload["created_at"]),
        auth_payload["nonce"],
        signature["address"] || signature[:address]
      ],
      ":"
    )
  end

  defp body_hash(body) do
    :crypto.hash(:sha256, body || "")
    |> Base.encode64()
  end

  defp signer_module(%module{}), do: module
end

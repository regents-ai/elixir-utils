defmodule SiwaKeyring.Auth do
  @drift_ms 30_000
  @request_id_pattern ~r/^[A-Za-z0-9._:-]{16,128}$/
  @signature_pattern ~r/^[a-f0-9]{64}$/

  def compute_hmac(secret, method, path, body, opts \\ []) do
    timestamp =
      Keyword.get_lazy(opts, :timestamp, fn ->
        Integer.to_string(System.system_time(:millisecond))
      end)

    request_id = Keyword.get_lazy(opts, :request_id, &request_id/0)
    payload = [String.upcase(method), path, request_id, timestamp, body] |> Enum.join("\n")

    signature =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    %{
      "x-keyring-timestamp" => timestamp,
      "x-keyring-request-id" => request_id,
      "x-keyring-signature" => signature
    }
  end

  def verify_hmac(secret, method, path, body, request_id, timestamp, signature) do
    with :ok <- validate_request_id(request_id),
         :ok <- validate_signature(signature),
         {:ok, _ts} <- fresh_timestamp(timestamp) do
      expected =
        compute_hmac(secret, method, path, body,
          request_id: request_id,
          timestamp: to_string(timestamp)
        )["x-keyring-signature"]

      if Plug.Crypto.secure_compare(expected, to_string(signature)) do
        :ok
      else
        {:error, :signature_mismatch}
      end
    end
  end

  def request_expires_at_ms(timestamp) do
    with {:ok, timestamp_ms} <- parse_timestamp(timestamp) do
      {:ok, timestamp_ms + @drift_ms}
    end
  end

  def request_id do
    "kr-" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
  end

  defp validate_request_id(request_id) when is_binary(request_id) do
    if Regex.match?(@request_id_pattern, request_id) do
      :ok
    else
      {:error, :invalid_request_id}
    end
  end

  defp validate_request_id(_request_id), do: {:error, :invalid_request_id}

  defp validate_signature(signature) when is_binary(signature) do
    if Regex.match?(@signature_pattern, signature) do
      :ok
    else
      {:error, :signature_mismatch}
    end
  end

  defp validate_signature(_signature), do: {:error, :signature_mismatch}

  defp fresh_timestamp(timestamp) do
    with {:ok, timestamp_ms} <- parse_timestamp(timestamp),
         true <- abs(System.system_time(:millisecond) - timestamp_ms) <= @drift_ms do
      {:ok, timestamp_ms}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :stale_or_invalid_timestamp}
    end
  end

  defp parse_timestamp(timestamp) do
    case Integer.parse(to_string(timestamp)) do
      {timestamp_ms, ""} -> {:ok, timestamp_ms}
      _result -> {:error, :stale_or_invalid_timestamp}
    end
  end
end

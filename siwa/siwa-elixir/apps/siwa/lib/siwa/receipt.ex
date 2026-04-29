defmodule Siwa.Receipt do
  @default_ttl_ms 30 * 60 * 1_000

  def create(payload, opts \\ []) do
    secret =
      Keyword.get_lazy(opts, :receipt_secret, fn ->
        Keyword.get(opts, :secret, Application.fetch_env!(:siwa, :receipt_secret))
      end)

    now = Keyword.get(opts, :now, DateTime.utc_now())
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    iat = DateTime.to_unix(now, :millisecond)
    exp = iat + ttl_ms

    payload =
      payload
      |> Enum.into(%{})
      |> Map.put_new("verified", "onchain")
      |> Map.put("iat", iat)
      |> Map.put("exp", exp)

    body = Jason.encode!(payload)
    encoded_body = Base.url_encode64(body, padding: false)
    mac = sign(encoded_body, secret)
    token = encoded_body <> "." <> mac

    {:ok, %{token: token, payload: payload, expires_at: DateTime.from_unix!(exp, :millisecond)}}
  end

  def verify(token, opts \\ [])

  def verify(token, opts) when is_binary(token) do
    secret =
      Keyword.get_lazy(opts, :receipt_secret, fn ->
        Keyword.get(opts, :secret, Application.fetch_env!(:siwa, :receipt_secret))
      end)

    now_ms =
      opts
      |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end)
      |> DateTime.to_unix(:millisecond)

    with {:ok, audience} <- required_audience(opts),
         [encoded_body, mac] <- String.split(token, ".", parts: 2),
         true <- secure_compare(mac, sign(encoded_body, secret)),
         {:ok, json} <- Base.url_decode64(encoded_body, padding: false),
         {:ok, payload} <- Jason.decode(json),
         exp when is_integer(exp) <- payload["exp"],
         true <- exp >= now_ms,
         :ok <- ensure_audience(payload, audience) do
      {:ok, payload}
    else
      {:error, :audience_required} -> {:error, :audience_required}
      {:error, :receipt_binding_mismatch} -> {:error, :receipt_binding_mismatch}
      _ -> {:error, :invalid_receipt}
    end
  end

  def verify(_token, _opts), do: {:error, :invalid_receipt}

  def default_ttl_ms, do: @default_ttl_ms

  defp sign(encoded_body, secret) do
    :crypto.mac(:hmac, :sha256, secret, encoded_body)
    |> Base.url_encode64(padding: false)
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash(:sha256, left) == :crypto.hash(:sha256, right) and
      Plug.Crypto.secure_compare(left, right)
  end

  defp secure_compare(_, _), do: false

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

  defp ensure_audience(%{"aud" => audience}, expected) when audience == expected, do: :ok
  defp ensure_audience(_payload, _expected), do: {:error, :receipt_binding_mismatch}
end

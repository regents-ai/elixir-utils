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

  def verify(token, opts \\ []) do
    secret =
      Keyword.get_lazy(opts, :receipt_secret, fn ->
        Keyword.get(opts, :secret, Application.fetch_env!(:siwa, :receipt_secret))
      end)

    now_ms = opts |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end) |> DateTime.to_unix(:millisecond)

    with [encoded_body, mac] <- String.split(token, ".", parts: 2),
         true <- secure_compare(mac, sign(encoded_body, secret)),
         {:ok, json} <- Base.url_decode64(encoded_body, padding: false),
         {:ok, payload} <- Jason.decode(json),
         true <- payload["exp"] >= now_ms,
         :ok <- ensure_audience(payload, opts) do
      {:ok, payload}
    else
      _ -> {:error, :invalid_receipt}
    end
  end

  def default_ttl_ms, do: @default_ttl_ms

  defp sign(encoded_body, secret) do
    :crypto.mac(:hmac, :sha256, secret, encoded_body)
    |> Base.url_encode64(padding: false)
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash(:sha256, left) == :crypto.hash(:sha256, right) and Plug.Crypto.secure_compare(left, right)
  end

  defp secure_compare(_, _), do: false

  defp ensure_audience(payload, opts) do
    case Keyword.get(opts, :audience) || Keyword.get(opts, :expected_audience) do
      nil ->
        :ok

      expected ->
        audience = payload["aud"] || payload["audience"]

        if audience == expected, do: :ok, else: {:error, :invalid_receipt}
    end
  end
end

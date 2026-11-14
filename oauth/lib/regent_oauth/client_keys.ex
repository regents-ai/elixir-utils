defmodule RegentOAuth.ClientKeys do
  @moduledoc """
  The public keys an app that signs its token requests publishes at its
  `jwks_uri` (`RegentOAuth.ClientAssertion`).

  They are read with `RegentHttp.Public`, as published identities are: HTTPS on
  port 443, public addresses only, no redirects, at most 16 KB, within five
  seconds. A set is kept for five minutes in Boruta's cache, the one that
  already holds the app's client row (`Boruta.Config.cache_backend/0`).

  A key id the kept set does not have reads the address again once, since the
  app may have rotated its keys, and such a read happens at most once a minute
  per address on each machine: an assertion naming an unknown key cannot make
  the site call the app's address more often than that. An address that does
  not answer, or answers with something that is not a key set, is not read
  again for a minute either. Nothing is retried.
  """

  @max_bytes 16_384
  @keep_ms 300_000
  @floor_ms 60_000

  @doc """
  The key `kid` names in the set published at `url`, usable to verify `alg`
  (`"RS256"` or `"ES256"`): `{:ok, %JOSE.JWK{}}`, `:unavailable` when the
  address does not answer just now, or `:error`.

  An assertion that names no `kid` may use the set's key only when the set has
  exactly one (OpenID Connect Core 1.0 section 10.1).
  """
  def key(url, kid, alg) do
    case cache().get({__MODULE__, url}) do
      {:ok, {:keys, keys}} ->
        with :error <- pick(keys, kid, alg) do
          if read_again?(url), do: read(url, kid, alg), else: :error
        end

      {:ok, nil} ->
        read(url, kid, alg)

      {:ok, failed} ->
        failed
    end
  end

  # Only the first unknown key id in a minute reads the address again.
  defp read_again?(url),
    do: cache().put_new({__MODULE__, :again, url}, true, ttl: @floor_ms) == {:ok, true}

  defp read(url, kid, alg) do
    case fetch(url) do
      {:ok, keys} ->
        :ok = cache().put({__MODULE__, url}, {:keys, keys}, ttl: @keep_ms)
        pick(keys, kid, alg)

      failed ->
        # A set already kept stays kept; only an address with none remembers
        # the failure, for as long as it is not read again.
        {:ok, _} = cache().put_new({__MODULE__, url}, failed, ttl: @floor_ms)
        failed
    end
  end

  defp fetch(url) do
    headers = [
      {"accept", "application/jwk-set+json, application/json"},
      {"user-agent", "RegentOAuth (+#{RegentOAuth.issuer()})"}
    ]

    result =
      case RegentHttp.Public.get(url, max_bytes: @max_bytes, headers: headers) do
        {:error, reason} when reason in [:timeout, :connection_error, :dns_error] -> :unavailable
        {:ok, %{status: status}} when status == 429 or status >= 500 -> :unavailable
        {:ok, %{status: 200, body: body}} -> parse(body)
        _refused -> :error
      end

    :telemetry.execute([:regent_oauth, :client_keys, :read], %{count: 1}, %{
      result: outcome(result)
    })

    result
  end

  defp outcome({:ok, _keys}), do: :ok
  defp outcome(:unavailable), do: :unavailable
  defp outcome(:error), do: :refused

  defp parse(body) do
    case Jason.decode(body) do
      {:ok, %{"keys" => [_ | _] = keys}} when length(keys) <= 20 ->
        if Enum.all?(keys, &is_map/1), do: {:ok, keys}, else: :error

      _ ->
        :error
    end
  end

  defp pick(keys, nil, alg) do
    case keys do
      [key] -> public(key, alg)
      _ -> :error
    end
  end

  defp pick(keys, kid, alg) do
    case Enum.filter(keys, &(&1["kid"] == kid)) do
      [key] -> public(key, alg)
      _ -> :error
    end
  end

  # A signing key of the type the algorithm needs, built from its public
  # members only. RFC 7518 section 3.3: an RSA key has at least 2048 bits.
  defp public(key, alg) do
    with true <- key["use"] in [nil, "sig"] and key["alg"] in [nil, alg],
         true <- key["key_ops"] == nil or (is_list(key["key_ops"]) and "verify" in key["key_ops"]),
         {:ok, members} <- members(key, alg) do
      {:ok, JOSE.JWK.from_map(members)}
    else
      _ -> :error
    end
  end

  defp members(%{"kty" => "RSA", "n" => n, "e" => e}, "RS256")
       when is_binary(n) and is_binary(e) do
    with {:ok, modulus} <- Base.url_decode64(n, padding: false),
         {:ok, <<_, _::binary>>} <- Base.url_decode64(e, padding: false),
         true <- :binary.decode_unsigned(modulus) >= Bitwise.bsl(1, 2047) do
      {:ok, %{"kty" => "RSA", "n" => n, "e" => e}}
    else
      _ -> :error
    end
  end

  defp members(%{"kty" => "EC", "crv" => "P-256", "x" => x, "y" => y}, "ES256")
       when is_binary(x) and is_binary(y) do
    with {:ok, <<_::binary-size(32)>>} <- Base.url_decode64(x, padding: false),
         {:ok, <<_::binary-size(32)>>} <- Base.url_decode64(y, padding: false) do
      {:ok, %{"kty" => "EC", "crv" => "P-256", "x" => x, "y" => y}}
    else
      _ -> :error
    end
  end

  defp members(_key, _alg), do: :error

  defp cache, do: Boruta.Config.cache_backend()
end

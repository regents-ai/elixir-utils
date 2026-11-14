defmodule RegentOAuth.ClientAssertion do
  @moduledoc """
  Client authentication at the token and revocation addresses.

  An app recorded with no method (`none`, a public client) authenticates with
  nothing: a request from it that carries a client assertion is refused
  (draft-ietf-oauth-client-id-metadata-document section 5). An app recorded
  with `private_key_jwt` (`RegentOAuth.ClientDocuments`) must send
  `client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer`
  and a `client_assertion` JWT on every request (RFC 7523 section 2.2, OpenID
  Connect Core 1.0 section 9), checked here before Boruta sees the request:

    * signed with RS256 or ES256 only, never `none` or a shared-secret
      algorithm, by a key from the app's `jwks_uri` (`RegentOAuth.ClientKeys`)
      chosen by the header's `kid`;
    * `iss` and `sub` both the app's `client_id` exactly;
    * `aud` names this server as its one value: its issuer (RFC 7523 as updated
      by RFC 10070) or its token address (OpenID Connect Core 1.0 section 9);
    * `exp` in the future and at most an hour away, `nbf` and `iat` (when sent)
      not more than a minute ahead;
    * `jti` used once: it is spent as a row of `oauth_tokens` whose unique
      `value` refuses a second one, on every machine.

  Boruta's own `private_key_jwt` check is not used: it runs only for
  confidential clients, takes the client from the assertion's `sub`, matches
  `aud` as a prefix, keeps no `jti`, reads the keys over its own HTTP client
  inside the token transaction and verifies RSA only.
  """

  alias Boruta.Ecto.{Client, Token}

  @type_urn "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @algorithms ["RS256", "ES256"]
  @max_lifetime 3_600
  @skew 60

  @doc "The signing algorithms an assertion may use."
  def algorithms, do: @algorithms

  @doc """
  The client an assertion names by its `sub`, read without checking anything.
  A request may name its client this way alone (RFC 7521 section 4.2);
  `authenticate/3` then checks the assertion against that client.
  """
  def subject(assertion) when is_binary(assertion) and byte_size(assertion) in 1..4096 do
    case Joken.peek_claims(assertion) do
      {:ok, %{"sub" => sub}} when is_binary(sub) -> {:ok, sub}
      _ -> :error
    end
  end

  def subject(_assertion), do: :error

  @doc """
  Checks a request's client authentication for the client row `client_id`,
  which the request named as `name` (its `client_id` or its assertion's
  `sub`): `:ok`, `{:error, :unavailable}` when the app's keys cannot be read
  just now, or `{:error, :invalid_client}`.
  """
  def authenticate(client_id, name, params) do
    case RegentOAuth.repo().get(Client, client_id, log: false) do
      %Client{token_endpoint_auth_methods: []} ->
        if Map.has_key?(params, "client_assertion") or
             Map.has_key?(params, "client_assertion_type"),
           do: {:error, :invalid_client},
           else: :ok

      %Client{token_endpoint_auth_methods: ["private_key_jwt"], jwks_uri: "https://" <> _ = keys} ->
        with @type_urn <- params["client_assertion_type"],
             assertion when is_binary(assertion) and byte_size(assertion) in 1..4096 <-
               params["client_assertion"] do
          verify(assertion, client_id, name, keys)
        else
          _ -> {:error, :invalid_client}
        end

      _ ->
        {:error, :invalid_client}
    end
  end

  defp verify(assertion, client_id, name, keys) do
    with {:ok, %{"alg" => alg} = header} when alg in @algorithms <- Joken.peek_header(assertion),
         false <- Map.has_key?(header, "crit"),
         kid when is_nil(kid) or is_binary(kid) <- header["kid"],
         {:ok, %{}} <- Joken.peek_claims(assertion),
         {:ok, key} <- RegentOAuth.ClientKeys.key(keys, kid, alg),
         {:ok, claims} <- Joken.verify(assertion, Joken.Signer.create(alg, key)),
         {:ok, jti, exp} <- claims(claims, name),
         :ok <- spend(client_id, jti, exp) do
      :ok
    else
      :unavailable -> {:error, :unavailable}
      _ -> {:error, :invalid_client}
    end
  end

  defp claims(claims, name) do
    now = System.system_time(:second)

    with true <- claims["iss"] == name and claims["sub"] == name,
         true <- audience?(claims["aud"]),
         exp when is_number(exp) and exp > now and exp <= now + @max_lifetime <- claims["exp"],
         true <- not_ahead?(claims["nbf"], now) and not_ahead?(claims["iat"], now),
         jti when is_binary(jti) and byte_size(jti) in 1..256 <- claims["jti"] do
      {:ok, jti, trunc(exp)}
    else
      _ -> :error
    end
  end

  # One value, compared as the exact string (RFC 3986 section 6.2.1).
  defp audience?([audience]) when is_binary(audience), do: audience?(audience)

  defp audience?(audience),
    do: audience in [RegentOAuth.issuer(), RegentOAuth.token_endpoint()]

  defp not_ahead?(nil, _now), do: true
  defp not_ahead?(time, now) when is_number(time), do: time <= now + @skew
  defp not_ahead?(_time, _now), do: false

  # The row is never a credential: no query that reads codes or tokens selects
  # its type. Its `value` is a hash, so any `jti` fits the unique index.
  defp spend(client_id, jti, exp) do
    now = DateTime.utc_now()

    row = %{
      id: Ecto.UUID.generate(),
      type: "client_assertion",
      value: RegentOAuth.hash_token(client_id <> ":" <> jti),
      client_id: client_id,
      sub: client_id,
      expires_at: exp,
      inserted_at: now,
      updated_at: now
    }

    case RegentOAuth.repo().insert_all(Token, [row], on_conflict: :nothing, log: false) do
      {1, _} -> :ok
      {0, _} -> :error
    end
  end
end

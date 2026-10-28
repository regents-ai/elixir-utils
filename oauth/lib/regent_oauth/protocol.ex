defmodule RegentOAuth.Protocol do
  @moduledoc "HTTP adaptation for Boruta; site routers supply fixed actions and rate limits."
  import Plug.Conn
  import Ecto.Query
  alias Boruta.Ecto.{Client, Token}
  alias RegentOAuth.Repo

  @behaviour Boruta.Oauth.TokenApplication
  @authorize_keys ~w(client_id redirect_uri response_type scope state resource code_challenge code_challenge_method)
  @token_keys ~w(client_id redirect_uri grant_type scope resource code code_verifier refresh_token)
  @register_keys ~w(client_name redirect_uris grant_types response_types token_endpoint_auth_method scope)

  def call(conn, action) do
    if RegentOAuth.enabled?(),
      do: dispatch(conn, action),
      else: json(conn, 404, %{error: "not_found"})
  rescue
    _ ->
      # Never expose Boruta structs, SQL parameters or exception text carrying credentials.
      :telemetry.execute([:regent_oauth, :request, :failure], %{count: 1}, %{})
      json(conn, 503, %{error: "temporarily_unavailable"})
  end

  defp dispatch(conn, :resource_metadata), do: json(conn, 200, RegentOAuth.resource_metadata())
  defp dispatch(conn, :server_metadata), do: json(conn, 200, RegentOAuth.server_metadata())

  defp dispatch(conn, :register) do
    params = conn.body_params

    with true <- bounded_map?(Map.take(params, @register_keys), @register_keys),
         true <- byte_size(Jason.encode!(params)) <= 8192,
         true <- Map.get(params, "token_endpoint_auth_method", "none") == "none",
         true <- Map.get(params, "response_types", ["code"]) == ["code"],
         true <-
           Map.get(params, "grant_types", ["authorization_code", "refresh_token"]) == [
             "authorization_code",
             "refresh_token"
           ],
         true <- RegentOAuth.valid_scopes?(Map.get(params, "scope", RegentOAuth.scope())),
         name when is_binary(name) <- Map.get(params, "client_name", "Connected app"),
         true <- String.length(name) in 1..100,
         uris when is_list(uris) and length(uris) in 1..5 <- params["redirect_uris"],
         true <- Enum.all?(uris, &redirect_uri?/1),
         {:ok, client} <-
           Boruta.Ecto.Admin.Clients.create_client(%{
             name: name,
             redirect_uris: Enum.uniq(uris),
             confidential: false,
             pkce: true,
             public_refresh_token: true,
             public_revoke: true,
             supported_grant_types: ["authorization_code", "refresh_token", "revoke"],
             token_endpoint_auth_methods: [],
             authorize_scope: true,
             authorized_scopes: Enum.map(RegentOAuth.scopes(), &%{name: &1}),
             access_token_ttl: 3600,
             authorization_code_ttl: 60,
             refresh_token_ttl: 2_592_000
           }) do
      json(conn, 201, %{
        client_id: client.id,
        client_name: client.name,
        redirect_uris: client.redirect_uris,
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
        token_endpoint_auth_method: "none",
        scope: Enum.join(RegentOAuth.scopes(), " ")
      })
    else
      _ -> json(conn, 400, %{error: "invalid_client_metadata"})
    end
  end

  defp dispatch(conn, :token) do
    params = conn.body_params

    with true <- bounded_map?(params, @token_keys),
         true <- params["resource"] == RegentOAuth.resource(),
         true <- RegentOAuth.valid_scopes?(Map.get(params, "scope", RegentOAuth.scope())),
         true <- params["grant_type"] in ["authorization_code", "refresh_token"],
         {:ok, _} <- Ecto.UUID.cast(params["client_id"]) do
      # The row lock serializes code consumption and refresh rotation, even if
      # two requests both saw a valid Boruta cache entry. All work is local DB/crypto.
      result =
        Repo.transaction(fn ->
          client_id = params["client_id"]
          Repo.one(from(c in Client, where: c.id == ^client_id, lock: "FOR UPDATE"))

          case lock_credential(params) do
            %Token{revoked_at: nil, refresh_token_revoked_at: revoked, client_id: ^client_id} =
                row
            when not is_nil(revoked) ->
              if params["grant_type"] == "refresh_token" and RegentOAuth.bound?(row.id) and
                   RegentOAuth.site().active_subject?(row.sub) do
                # Boruta rotates refresh tokens. Proven reuse revokes this
                # subject's app connection, as required by RFC 9700 section 4.14.2.
                {:ok, :ok} = RegentOAuth.revoke_client(row.sub, row.client_id)
                {:denied, :invalid_grant}
              else
                Repo.rollback(:invalid_grant)
              end

            %Token{revoked_at: nil} = row ->
              if RegentOAuth.bound?(row.id) and RegentOAuth.site().active_subject?(row.sub) and
                   active_credential?(row, params) do
                # Token requests use only the allowlisted form body. In particular,
                # query request objects must never trigger HTTP under these locks.
                request = %{conn | query_params: %{}, query_string: "", params: params}

                case Boruta.Oauth.token(request, RegentOAuth.TokenResult) do
                  {:ok, response} -> response
                  {:error, error} -> Repo.rollback(error)
                end
              else
                Repo.rollback(:invalid_grant)
              end

            _ ->
              Repo.rollback(:invalid_grant)
          end
        end)

      # No response is sent until the transaction has committed.
      case result do
        {:ok, {:denied, error}} -> token_error(conn, error)
        {:ok, response} -> token_success(conn, response)
        {:error, error} -> token_error(conn, error)
      end
    else
      _ -> json(conn, 400, %{error: "invalid_request"})
    end
  end

  defp dispatch(conn, :revoke) do
    params = conn.body_params

    if bounded_map?(params, ~w(client_id token token_type_hint)) and
         match?({:ok, _}, Ecto.UUID.cast(params["client_id"])) and
         is_binary(params["token"]) and byte_size(params["token"]) in 1..4096 do
      {:ok, :ok} =
        Repo.transaction(fn ->
          client_id = params["client_id"]
          Repo.one(from(c in Client, where: c.id == ^client_id, lock: "FOR UPDATE"))

          hash = RegentOAuth.hash_token(params["token"])

          token =
            Repo.one(
              from(t in Token,
                where:
                  t.client_id == ^client_id and t.type == "access_token" and is_nil(t.revoked_at) and
                    (t.value == ^hash or t.refresh_token == ^hash)
              )
            )

          if token && RegentOAuth.bound?(token.id) do
            # A refresh may already have rotated this credential. Revoke the
            # connection under the issuance lock so no successor survives.
            {:ok, :ok} = RegentOAuth.revoke_client(token.sub, client_id)
          end

          :ok
        end)

      # Unknown tokens and tokens belonging to another client reveal nothing.
      json(conn, 200, %{})
    else
      json(conn, 400, %{error: "invalid_request"})
    end
  end

  defp lock_credential(%{"grant_type" => "authorization_code", "code" => code})
       when is_binary(code),
       do:
         Repo.one(
           from(t in Token, where: t.type == "code" and t.value == ^code, lock: "FOR UPDATE")
         )

  defp lock_credential(%{"grant_type" => "refresh_token", "refresh_token" => token})
       when is_binary(token) do
    hash = RegentOAuth.hash_token(token)

    Repo.one(
      from(t in Token,
        where: t.type == "access_token" and t.refresh_token == ^hash,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_credential(_), do: nil

  defp active_credential?(%Token{client_id: client, expires_at: expiry}, %{
         "grant_type" => "authorization_code",
         "client_id" => client
       }),
       do: expiry > System.system_time(:second)

  defp active_credential?(
         %Token{client_id: client, refresh_token_revoked_at: nil, inserted_at: inserted},
         %{"grant_type" => "refresh_token", "client_id" => client}
       ),
       do: DateTime.diff(DateTime.utc_now(), inserted) < 2_592_000

  defp active_credential?(_, _), do: false

  @impl true
  def token_success(conn, response) do
    json(conn, 200, %{
      access_token: response.access_token,
      token_type: response.token_type,
      expires_in: response.expires_in,
      refresh_token: response.refresh_token,
      scope: response.token.scope
    })
  end

  @impl true
  def token_error(conn, error), do: json(conn, 400, %{error: error_name(error)})

  @doc false
  def authorize_params?(params) do
    bounded_map?(params, @authorize_keys) and
      params["resource"] == RegentOAuth.resource() and RegentOAuth.valid_scopes?(params["scope"]) and
      params["response_type"] == "code" and params["code_challenge_method"] == "S256" and
      is_binary(params["state"]) and byte_size(params["state"]) > 0 and
      is_binary(params["code_challenge"]) and
      Regex.match?(~r/\A[A-Za-z0-9_-]{43}\z/, params["code_challenge"])
  end

  @doc false
  def request_client(params) do
    with {:ok, id} <- Ecto.UUID.cast(params["client_id"]),
         %Client{confidential: false, pkce: true} = client <- Repo.get(Client, id),
         true <- params["redirect_uri"] in client.redirect_uris do
      ensure_client_scopes(client)
    else
      _ -> {:error, :invalid_client}
    end
  end

  # Eligible client scopes are not user grants. Existing DCR clients can ask for
  # a newly supported permission, but Boruta still requires fresh human consent
  # and keeps code/refresh tokens limited to their actual granted scopes.
  defp ensure_client_scopes(client) do
    Repo.transaction(fn ->
      locked = Repo.one!(from(c in Client, where: c.id == ^client.id, lock: "FOR UPDATE"))
      current = Repo.preload(locked, :authorized_scopes)
      existing = Enum.map(current.authorized_scopes, & &1.name) |> Enum.sort()
      configured = Enum.sort(RegentOAuth.scopes())

      if existing == configured do
        current
      else
        case Boruta.Ecto.Admin.Clients.update_client(current, %{
               authorized_scopes: Enum.map(configured, &%{name: &1})
             }) do
          {:ok, updated} -> updated
          {:error, _} -> Repo.rollback(:invalid_client)
        end
      end
    end)
  end

  defp redirect_uri?(value) when is_binary(value) and byte_size(value) <= 2048 do
    local? = URI.parse(RegentOAuth.issuer()).host in ["localhost", "127.0.0.1"]

    with {:ok, uri} <- URI.new(value) do
      (uri.scheme == "https" or
         (local? and uri.scheme == "http" and uri.host in ["localhost", "127.0.0.1"])) and
        is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and is_nil(uri.fragment) and
        not Regex.match?(~r/[\x00-\x20\x7f\\*]/, value)
    else
      _ -> false
    end
  end

  defp redirect_uri?(_), do: false

  defp bounded_map?(params, keys) when is_map(params) do
    not is_struct(params) and Map.keys(params) -- keys == [] and
      byte_size(Jason.encode!(params)) <= 8192
  end

  defp bounded_map?(_, _), do: false

  defp error_name(%{error: error})
       when error in [
              :invalid_client,
              :invalid_request,
              :invalid_scope,
              :invalid_grant,
              :unsupported_grant_type,
              :unauthorized_client
            ],
       do: Atom.to_string(error)

  defp error_name(:invalid_grant), do: "invalid_grant"
  defp error_name(_), do: "invalid_request"

  def json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end

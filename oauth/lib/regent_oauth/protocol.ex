defmodule RegentOAuth.Protocol do
  @moduledoc """
  HTTP adaptation for Boruta; site routers supply fixed actions and rate limits.
  Every refusal names its reason (`RegentOAuth.Refusal`).
  """
  import Plug.Conn
  import Ecto.Query
  import RegentOAuth.Refusal, only: [check: 2]
  alias Boruta.Ecto.{Client, Token}
  alias RegentOAuth.{ClientAssertion, ClientDocuments, Refusal}

  @behaviour Boruta.Oauth.TokenApplication
  @authorize_keys ~w(client_id redirect_uri response_type scope state resource code_challenge code_challenge_method)
  @assertion_keys ~w(client_assertion_type client_assertion)
  @token_keys ~w(client_id redirect_uri grant_type scope resource code code_verifier refresh_token) ++
                @assertion_keys
  @revoke_keys ~w(client_id token token_type_hint) ++ @assertion_keys
  @register_keys ~w(client_name redirect_uris grant_types response_types token_endpoint_auth_method scope)
  @oauth_errors [
    :invalid_client,
    :invalid_request,
    :invalid_scope,
    :invalid_grant,
    :unsupported_grant_type,
    :unauthorized_client
  ]
  @refresh_grace_seconds 30

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

    with :ok <- bounded(Map.take(params, @register_keys), @register_keys),
         :ok <- check(byte_size(Jason.encode!(params)) <= 8192, :too_large),
         :ok <-
           check(
             Map.get(params, "token_endpoint_auth_method", "none") == "none",
             :token_endpoint_auth_method
           ),
         :ok <- check(Map.get(params, "response_types", ["code"]) == ["code"], :response_types),
         grant_types = Map.get(params, "grant_types", ["authorization_code", "refresh_token"]),
         :ok <-
           check(
             is_list(grant_types) and
               Enum.sort(grant_types) == ["authorization_code", "refresh_token"],
             :grant_types
           ),
         # A requested `scope` is not checked: every client is registered for
         # the configured scopes (RFC 7591 section 3.2.1), and each sign-in
         # still asks the person for exactly what it grants.
         name = Map.get(params, "client_name", "Connected app"),
         :ok <- check(is_binary(name) and String.length(name) in 1..100, :client_name),
         uris = params["redirect_uris"],
         :ok <- check(is_list(uris) and length(uris) in 1..5, :redirect_uris),
         :ok <- check(Enum.all?(uris, &redirect_uri?/1), :redirect_uri_format),
         {:ok, client} <- register_client(name, Enum.uniq(uris)) do
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
      {:error, reason} -> Refusal.answer(conn, :register, 400, "invalid_client_metadata", reason)
    end
  end

  defp dispatch(conn, :token) do
    params = conn.body_params

    with :ok <- bounded(params, @token_keys),
         :ok <- check(resource?(params), :resource),
         :ok <-
           check(RegentOAuth.valid_scopes?(Map.get(params, "scope", RegentOAuth.scope())), :scope),
         :ok <-
           check(params["grant_type"] in ["authorization_code", "refresh_token"], :grant_type),
         {:ok, name} <- client_name(params),
         {:ok, client_id} <- resolve_client(name, :stored),
         # Before anything is read under a lock: reading the app's keys may
         # call its address, never inside the transaction.
         :ok <- ClientAssertion.authenticate(client_id, name, params) do
      # From here the request names the client's own row, and Boruta never
      # sees the assertion: it would take the client from its `sub`.
      params = params |> Map.drop(@assertion_keys) |> Map.put("client_id", client_id)

      # The connection's lock serializes code consumption, refresh rotation and
      # disconnect for one person and app, even if two requests both saw a valid
      # Boruta cache entry. A credential that is not this app's takes no lock, so
      # an unknown code holds up nobody: every person's Claude connection shares
      # one client row. All work is local DB/crypto.
      result =
        RegentOAuth.repo().transaction(fn ->
          with {:ok, query} <- credential_query(params),
               {:ok, sub} <-
                 credential_subject(RegentOAuth.repo().one(query, log: false), client_id),
               :ok <- RegentOAuth.lock_connection(sub, client_id) do
            issue(
              conn,
              params,
              client_id,
              RegentOAuth.repo().one(lock(query, "FOR UPDATE"), log: false)
            )
          else
            {:error, reason} -> RegentOAuth.repo().rollback({:invalid_grant, reason})
          end
        end)

      # No response is sent until the transaction has committed.
      case result do
        {:ok, {:denied, error}} -> token_error(conn, error)
        {:ok, response} -> token_success(conn, response)
        {:error, error} -> token_error(conn, error)
      end
    else
      refused -> refuse(conn, :token, refused)
    end
  end

  defp dispatch(conn, :revoke) do
    params = conn.body_params

    with :ok <- bounded(params, @revoke_keys),
         :ok <-
           check(is_binary(params["token"]) and byte_size(params["token"]) in 1..4096, :token),
         {:ok, name} <- client_name(params),
         {:ok, client_id} <- resolve_client(name, :stored),
         :ok <- ClientAssertion.authenticate(client_id, name, params) do
      hash = RegentOAuth.hash_token(params["token"])

      token =
        RegentOAuth.repo().one(
          from(t in Token,
            where:
              t.client_id == ^client_id and t.type == "access_token" and is_nil(t.revoked_at) and
                (t.value == ^hash or t.refresh_token == ^hash)
          ),
          log: false
        )

      if token && RegentOAuth.bound?(token.id) do
        # A refresh may already have rotated this credential. revoke_client takes
        # the connection's lock, so no successor survives.
        {:ok, :ok} = RegentOAuth.revoke_client(token.sub, client_id)
      end

      # Unknown tokens and tokens belonging to another client reveal nothing.
      json(conn, 200, %{})
    else
      refused -> refuse(conn, :revoke, refused)
    end
  end

  defp register_client(name, uris) do
    case Boruta.Ecto.Admin.Clients.create_client(public_client(name, uris)) do
      {:ok, client} -> {:ok, client}
      {:error, _changeset} -> {:error, :client_not_saved}
    end
  end

  # A request names its client by `client_id`, or by its assertion alone
  # (RFC 7521 section 4.2), which must then name that same client.
  defp client_name(%{"client_id" => name}), do: {:ok, name}
  defp client_name(%{"client_assertion" => assertion}), do: ClientAssertion.subject(assertion)
  defp client_name(_params), do: {:error, :no_client}

  # RFC 6749 section 5.2: a client that fails authentication is answered
  # `invalid_client` with a 401, with one description whatever the reason.
  defp refuse(conn, endpoint, {:error, {:invalid_client, reason}}),
    do: Refusal.answer(conn, endpoint, 401, "invalid_client", reason, :invalid_client)

  defp refuse(conn, endpoint, {:error, :unavailable}),
    do: Refusal.answer(conn, endpoint, 503, "temporarily_unavailable", :unavailable)

  defp refuse(conn, endpoint, {:error, reason}),
    do: Refusal.answer(conn, endpoint, 400, "invalid_request", reason)

  # Runs under the connection's lock, with the credential read again under its
  # row lock after the wait.
  defp issue(conn, params, client_id, credential) do
    case credential do
      %Token{revoked_at: nil, refresh_token_revoked_at: revoked, client_id: ^client_id} =
          row
      when not is_nil(revoked) ->
        with :ok <- check(params["grant_type"] == "refresh_token", :revoked),
             :ok <- check(RegentOAuth.bound?(row.id), :not_bound),
             :ok <- check(RegentOAuth.site().active_subject?(row.sub), :inactive_subject),
             :ok <-
               check(
                 DateTime.diff(DateTime.utc_now(), revoked) >= @refresh_grace_seconds,
                 :refresh_used_within_grace
               ) do
          # Boruta rotates refresh tokens. Proven reuse revokes this
          # subject's app connection, as required by RFC 9700 section 4.14.2.
          # A second refresh within the grace period is the app's own
          # retry or overlap, not a stolen token: it is only refused.
          {:ok, :ok} = RegentOAuth.revoke_client(row.sub, row.client_id)
          {:denied, {:invalid_grant, :refresh_reuse_revoked}}
        else
          {:error, reason} -> RegentOAuth.repo().rollback({:invalid_grant, reason})
        end

      %Token{revoked_at: nil} = row ->
        with :ok <- check(RegentOAuth.bound?(row.id), :not_bound),
             :ok <- check(RegentOAuth.site().active_subject?(row.sub), :inactive_subject),
             :ok <- active_credential(row, params) do
          # Token requests use only the allowlisted form body. In particular,
          # query request objects must never trigger HTTP under these locks.
          request = %{
            conn
            | query_params: %{},
              query_string: "",
              body_params: params,
              params: params
          }

          case Boruta.Oauth.token(request, RegentOAuth.TokenResult) do
            {:ok, response} -> response
            {:error, error} -> RegentOAuth.repo().rollback(error)
          end
        else
          {:error, reason} -> RegentOAuth.repo().rollback({:invalid_grant, reason})
        end

      nil ->
        RegentOAuth.repo().rollback({:invalid_grant, :unknown_credential})

      %Token{} ->
        RegentOAuth.repo().rollback({:invalid_grant, :revoked})
    end
  end

  defp credential_query(%{"grant_type" => "authorization_code", "code" => code})
       when is_binary(code),
       do: {:ok, from(t in Token, where: t.type == "code" and t.value == ^code)}

  defp credential_query(%{"grant_type" => "refresh_token", "refresh_token" => token})
       when is_binary(token) do
    hash = RegentOAuth.hash_token(token)
    {:ok, from(t in Token, where: t.type == "access_token" and t.refresh_token == ^hash)}
  end

  defp credential_query(_), do: {:error, :missing_credential}

  # The person a credential was issued to, when it is this app's.
  defp credential_subject(nil, _client_id), do: {:error, :unknown_credential}

  defp credential_subject(%Token{client_id: client_id, sub: sub}, client_id) when is_binary(sub),
    do: {:ok, sub}

  defp credential_subject(%Token{client_id: client_id}, client_id), do: {:error, :no_subject}
  defp credential_subject(%Token{}, _client_id), do: {:error, :other_client}

  defp active_credential(%Token{client_id: client, expires_at: expiry}, %{
         "grant_type" => "authorization_code",
         "client_id" => client
       }),
       do: check(expiry > System.system_time(:second), :expired)

  defp active_credential(
         %Token{client_id: client, refresh_token_revoked_at: nil, inserted_at: inserted},
         %{"grant_type" => "refresh_token", "client_id" => client}
       ),
       do: check(DateTime.diff(DateTime.utc_now(), inserted) < 2_592_000, :expired)

  defp active_credential(_, _), do: {:error, :other_client}

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

  # A code or refresh token that fails is answered with one description; the
  # log line alone names why.
  @impl true
  def token_error(conn, {:invalid_grant, reason}),
    do: Refusal.answer(conn, :token, 400, "invalid_grant", reason, :invalid_grant)

  def token_error(conn, %Boruta.Oauth.Error{error: error}) when error in @oauth_errors,
    do: Refusal.answer(conn, :token, 400, Atom.to_string(error), error)

  # Any other refusal is answered `invalid_request`, logged by Boruta's error
  # name when it is one. Never the error itself: Boruta may describe a failure
  # with the request's values.
  def token_error(conn, %Boruta.Oauth.Error{error: error}) when is_atom(error),
    do: Refusal.answer(conn, :token, 400, "invalid_request", error, :unexpected)

  def token_error(conn, _error),
    do: Refusal.answer(conn, :token, 400, "invalid_request", :unexpected)

  @doc false
  def authorize_params(params) do
    with :ok <- bounded(params, @authorize_keys),
         :ok <- check(params["resource"] == RegentOAuth.resource(), :resource),
         :ok <- check(RegentOAuth.valid_scopes?(params["scope"]), :scope),
         :ok <- check(params["response_type"] == "code", :response_type),
         :ok <- check(params["code_challenge_method"] == "S256", :code_challenge_method),
         :ok <- check(is_binary(params["state"]) and byte_size(params["state"]) > 0, :state) do
      check(
        is_binary(params["code_challenge"]) and
          Regex.match?(~r/\A[A-Za-z0-9_-]{43}\z/, params["code_challenge"]),
        :code_challenge
      )
    end
  end

  @doc """
  The client row an authorization request names, for a person about to
  approve it: a published identity is read again first when it is due.
  `{:error, :unavailable}` when its address does not answer just now, or
  `{:error, reason}` naming the check that refused.
  """
  def request_client(params) do
    with {:ok, id} <- resolve_client(params["client_id"], :current),
         {:ok, client} <- public_row(RegentOAuth.repo().get(Client, id, log: false)),
         :ok <- check(params["redirect_uri"] in client.redirect_uris, :redirect_uri) do
      {:ok, client}
    end
  end

  defp public_row(%Client{confidential: false, pkce: true} = client), do: {:ok, client}
  defp public_row(nil), do: {:error, :client_id}
  defp public_row(%Client{}), do: {:error, :client_not_public}

  # A published identity's address resolves only through the documents it was
  # recorded from, and a registered client's id only when no document recorded
  # it: neither is ever taken for the other.
  defp resolve_client(value, moment) do
    cond do
      ClientDocuments.address?(value) and moment == :current ->
        ClientDocuments.current(value)

      ClientDocuments.address?(value) ->
        case ClientDocuments.stored(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, :client_id}
        end

      true ->
        with {:ok, id} <- Ecto.UUID.cast(value),
             false <- ClientDocuments.document_client?(id) do
          {:ok, id}
        else
          _ -> {:error, :client_id}
        end
    end
  end

  @doc "A public client's row: S256 PKCE, the code and refresh grants, and every configured scope."
  def public_client(name, redirect_uris) do
    %{
      name: name,
      redirect_uris: redirect_uris,
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
    }
  end

  # Every request names the one resource, except that a refresh may leave it
  # out (RFC 8707 makes it optional there): the token already names it.
  defp resource?(%{"grant_type" => "refresh_token"} = params),
    do: params["resource"] in [nil, RegentOAuth.resource()]

  defp resource?(params), do: params["resource"] == RegentOAuth.resource()

  @doc false
  def redirect_uri?(value) when is_binary(value) and byte_size(value) <= 2048 do
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

  def redirect_uri?(_), do: false

  # A plain map of only the allowed keys, at most 8 KB as JSON.
  defp bounded(params, keys) when is_map(params) and not is_struct(params) do
    with :ok <- check(Map.keys(params) -- keys == [], :unexpected_parameter),
         do: check(byte_size(Jason.encode!(params)) <= 8192, :too_large)
  end

  defp bounded(_params, _keys), do: {:error, :body}

  def json(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end

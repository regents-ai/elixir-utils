defmodule RegentOAuth do
  @moduledoc """
  Boruta authorization-code/PKCE integration for one site's MCP resource.

  The site supplies a verified Privy subject, its existing account checks, its
  schema and the permitted scopes. Boruta owns codes, tokens, PKCE and refresh.
  A provider instance issues for exactly one fixed resource: authorize and token
  requests must name it, and the resource server refuses any other audience.
  Opaque tokens are issuer-bound to this provider's own database schema.

  Its rows live in the site's own schema and go through the site's repository
  and pool (`repo/0`): the repository puts that schema on every query, as each
  Regent site's does in `default_options/1`, and `configure/1` refuses one that
  does not. The provider starts no repository, and its own reads and writes are
  never logged (`log: false`): they carry authorization codes and token hashes.
  """

  import Ecto.Query
  alias Boruta.Ecto.{Client, Token}

  @callback config() :: keyword()
  @callback repo() :: module()
  @callback current_subject(Plug.Conn.t()) :: String.t() | nil
  @callback active_subject?(String.t()) :: boolean()

  def site, do: Application.fetch_env!(:regent_oauth, :site)
  def repo, do: site().repo()
  def config, do: site().config()
  def enabled?, do: Keyword.get(config(), :enabled?, false)
  def resource, do: Keyword.fetch!(config(), :resource)
  def issuer, do: Keyword.fetch!(config(), :issuer)
  def scope, do: Keyword.fetch!(config(), :scope)
  def scopes, do: [scope() | Map.keys(Keyword.get(config(), :additional_scopes, %{}))]

  def valid_scopes?(value) when is_binary(value) do
    requested = String.split(value)

    requested != [] and length(requested) == length(Enum.uniq(requested)) and
      Enum.all?(requested, &(&1 in scopes()))
  end

  def valid_scopes?(_), do: false

  def permission_descriptions(value) do
    descriptions =
      Map.put(
        Keyword.get(config(), :additional_scopes, %{}),
        scope(),
        Keyword.fetch!(config(), :permission_description)
      )

    value |> String.split() |> Enum.map(&Map.fetch!(descriptions, &1))
  end

  @doc "Configure before the site's supervision tree starts; never starts a server or migrates."
  def configure(site) do
    config = site.config()

    if Keyword.get(config, :enabled?, false) do
      issuer = URI.parse(Keyword.fetch!(config, :issuer))
      resource = URI.parse(Keyword.fetch!(config, :resource))
      local? = issuer.scheme == "http" and issuer.host in ["localhost", "127.0.0.1"]
      valid = issuer.scheme == "https" or local?

      if not (valid and is_binary(issuer.host) and issuer.path in [nil, ""] and
                is_nil(issuer.query) and is_nil(issuer.fragment) and is_nil(issuer.userinfo) and
                is_binary(resource.host) and is_nil(resource.query) and is_nil(resource.fragment) and
                is_nil(resource.userinfo) and
                (resource.scheme == "https" or
                   (local? and resource.scheme == "http" and
                      resource.host in ["localhost", "127.0.0.1"])) and
                Regex.match?(~r/\A[a-z][a-z0-9_.:-]{0,127}\z/, Keyword.fetch!(config, :scope))) do
        raise ArgumentError,
              "OAuth requires a fixed HTTPS issuer, resource and scope (loopback HTTP is local-only)"
      end
    end

    additional = Keyword.get(config, :additional_scopes, %{})

    unless is_map(additional) and
             Enum.all?(additional, fn {name, description} ->
               is_binary(name) and Regex.match?(~r/\A[a-z][a-z0-9_.:-]{0,127}\z/, name) and
                 is_binary(description) and byte_size(description) in 1..500
             end),
           do:
             raise(
               ArgumentError,
               "OAuth additional scopes require bounded names and permission descriptions"
             )

    note = Keyword.get(config, :consent_note)

    unless is_nil(note) or (is_binary(note) and byte_size(note) in 1..500),
      do: raise(ArgumentError, "OAuth consent_note must be bounded text")

    prefix = site.repo().default_options(:all)[:prefix]

    unless is_binary(prefix) and prefix != "",
      do:
        raise(
          ArgumentError,
          "OAuth requires a site repository that puts the site's schema on every query"
        )

    Application.put_env(:regent_oauth, :site, site)

    Application.put_env(:boruta, Boruta.Oauth,
      repo: site.repo(),
      issuer: Keyword.fetch!(config, :issuer),
      contexts: [
        access_tokens: RegentOAuth.AccessTokens,
        resource_owners: RegentOAuth.ResourceOwners
      ],
      max_ttl: [
        authorization_code: 60,
        access_token: 3600,
        id_token: 3600,
        refresh_token: 2_592_000
      ]
    )

    :ok
  end

  @doc "The resource metadata a connected app discovers from a Bearer challenge."
  def resource_metadata do
    %{
      resource: resource(),
      authorization_servers: [issuer()],
      scopes_supported: scopes(),
      bearer_methods_supported: ["header"]
    }
  end

  @doc "Discovery for the supported authorization-code + S256 PKCE and DCR flow."
  def server_metadata do
    %{
      issuer: issuer(),
      authorization_endpoint: issuer() <> "/oauth/authorize",
      token_endpoint: issuer() <> "/oauth/token",
      registration_endpoint: issuer() <> "/oauth/register",
      revocation_endpoint: issuer() <> "/oauth/revoke",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      token_endpoint_auth_methods_supported: ["none"],
      code_challenge_methods_supported: ["S256"],
      scopes_supported: scopes()
    }
  end

  def challenge(required_scope \\ scope()) do
    ~s(Bearer resource_metadata="#{issuer()}/.well-known/oauth-protected-resource", scope="#{required_scope}")
  end

  @doc "Verify with Boruta, then recheck the authoritative row to defeat stale cache entries."
  def verify(bearer, expected_resource, required_scope \\ scope())

  def verify(bearer, expected_resource, required_scope)
      when is_binary(bearer) and byte_size(bearer) in 1..4096 do
    with true <- enabled?() and expected_resource == resource(),
         {:ok, _} <- Boruta.Oauth.Authorization.AccessToken.authorize(value: bearer),
         %Token{} = token <-
           repo().get_by(Token, [value: hash_token(bearer), type: "access_token"], log: false),
         true <- live?(token) and required_scope in String.split(token.scope) do
      {:ok, principal(token)}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def verify(_, _, _), do: {:error, :unauthorized}

  @doc """
  The stored form of an access or refresh token: its SHA-256 hash in lowercase
  hex. Only this is kept; the plain token reaches the client once.
  """
  def hash_token(token) when is_binary(token),
    do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  @doc "Recheck delivery authority without retaining a bearer token in a subscription."
  def live_token?(id, subject, client_id) do
    enabled?() and
      case repo().get(Token, id, log: false) do
        %Token{sub: ^subject, client_id: ^client_id} = token -> live?(token)
        _ -> false
      end
  end

  defp live?(%Token{
         id: id,
         type: "access_token",
         revoked_at: nil,
         sub: subject,
         expires_at: expires_at,
         scope: granted,
         client_id: client_id
       })
       when is_binary(subject) and is_integer(expires_at) do
    bound?(id) and expires_at > System.system_time(:second) and
      valid_scopes?(granted) and
      site().active_subject?(subject) and
      public_client?(repo().get(Client, client_id, log: false))
  end

  defp live?(_), do: false

  @doc """
  Write this provider's issuer and resource on the stored code or token `id`,
  as it is issued. Boruta's rows carry neither, so each issue writes them here.
  """
  def bind(id) do
    {1, _} =
      repo().update_all(
        from(t in "oauth_tokens", where: t.id == type(^id, :binary_id)),
        [set: [oauth_issuer: issuer(), mcp_resource: resource()]],
        log: false
      )

    :ok
  end

  @doc "`bind/1` for the authorization code Boruta has just stored."
  def bind_code(code) when is_binary(code) do
    repo().one!(from(t in Token, where: t.type == "code" and t.value == ^code, select: t.id),
      log: false
    )
    |> bind()
  end

  @doc "Check the issuer and audience written on the code or token at issuance."
  def bound?(id) do
    repo().exists?(
      from(t in "oauth_tokens",
        where:
          t.id == type(^id, :binary_id) and t.oauth_issuer == ^issuer() and
            t.mcp_resource == ^resource()
      ),
      log: false
    )
  end

  defp public_client?(%Client{confidential: false, pkce: true, supported_grant_types: types}) do
    "authorization_code" in types and
      Enum.all?(types, &(&1 in ["authorization_code", "refresh_token", "revoke"]))
  end

  defp public_client?(_), do: false

  defp principal(token) do
    %{
      token_id: token.id,
      subject: token.sub,
      client_id: token.client_id,
      expires_at: DateTime.from_unix!(token.expires_at),
      resource: resource(),
      issuer: issuer(),
      scopes: String.split(token.scope)
    }
  end

  @doc "Only public client metadata for the authenticated subject's connected apps."
  def connected_clients(subject) do
    repo().all(
      from(c in Client,
        join: t in Token,
        on: t.client_id == c.id,
        where: t.sub == ^subject and t.type == "access_token" and is_nil(t.revoked_at),
        distinct: c.id,
        select: %{id: c.id, name: c.name}
      ),
      log: false
    )
  end

  @doc "Revoke this person's app connection, including all access and refresh tokens."
  def revoke_client(subject, client_id) do
    repo().transaction(fn ->
      # Token issuance takes this same standard row lock. A concurrent refresh
      # cannot commit an unseen successor after disconnect has scanned its tokens.
      repo().one(from(c in Client, where: c.id == ^client_id, lock: "FOR UPDATE"), log: false)

      mine = from(t in Token, where: t.sub == ^subject and t.client_id == ^client_id)
      tokens = repo().all(mine, log: false)
      now = DateTime.utc_now()
      repo().update_all(mine, [set: [revoked_at: now, refresh_token_revoked_at: now]], log: false)

      # Boruta caches authorization codes; access tokens are never cached
      # (`RegentOAuth.AccessTokens`). The database check remains decisive.
      tokens
      |> Enum.filter(&(&1.type == "code"))
      |> Enum.each(fn token ->
        token |> Boruta.Ecto.OauthMapper.to_oauth_schema() |> Boruta.Ecto.TokenStore.invalidate()
      end)

      :ok
    end)
  end
end

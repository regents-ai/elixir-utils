defmodule RegentOAuth do
  @moduledoc """
  Boruta authorization-code/PKCE integration for one site's MCP resource.

  The site supplies a verified Privy subject, its existing account checks, its
  schema and the permitted scopes. Boruta owns codes, tokens, PKCE and refresh.
  A provider instance issues for exactly one fixed resource: authorize and token
  requests must name it, and the resource server refuses any other audience.
  Opaque tokens are issuer-bound to this provider's own database schema.
  """

  import Ecto.Query
  alias Boruta.Ecto.{Client, Token}
  alias RegentOAuth.Repo

  @callback config() :: keyword()
  @callback repo() :: module()
  @callback current_subject(Plug.Conn.t()) :: String.t() | nil
  @callback active_subject?(String.t()) :: boolean()

  def site, do: Application.fetch_env!(:regent_oauth, :site)
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

    Application.put_env(:regent_oauth, :site, site)
    Application.put_env(:regent_oauth, :prefix, site.repo().default_prefix())

    Application.put_env(
      :regent_oauth,
      Repo,
      site.repo().config()
      |> Keyword.drop([:name, :pool])
      |> Keyword.merge(pool_size: 2, log: false, show_sensitive_data_on_connection_error: false)
    )

    Application.put_env(:boruta, Boruta.Oauth,
      repo: Repo,
      issuer: Keyword.fetch!(config, :issuer),
      contexts: [resource_owners: RegentOAuth.ResourceOwners],
      max_ttl: [
        authorization_code: 60,
        access_token: 3600,
        id_token: 3600,
        refresh_token: 2_592_000
      ]
    )

    :ok
  end

  @doc "The resource metadata ChatGPT discovers from a Bearer challenge."
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
         %Token{} = token <- Repo.get_by(Token, value: bearer, type: "access_token"),
         true <- live?(token) and required_scope in String.split(token.scope) do
      {:ok, principal(token)}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def verify(_, _, _), do: {:error, :unauthorized}

  @doc "Recheck delivery authority without retaining a bearer token in a subscription."
  def live_token?(id, subject, client_id) do
    enabled?() and
      case Repo.get(Token, id) do
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
      site().active_subject?(subject) and public_client?(Repo.get(Client, client_id))
  end

  defp live?(_), do: false

  @doc "Check the audience and issuer frozen by the provider schema at issuance."
  def bound?(id) do
    Repo.exists?(
      from(t in "oauth_tokens",
        where:
          t.id == type(^id, :binary_id) and t.oauth_issuer == ^issuer() and
            t.mcp_resource == ^resource()
      )
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
    Repo.all(
      from(c in Client,
        join: t in Token,
        on: t.client_id == c.id,
        where: t.sub == ^subject and t.type == "access_token" and is_nil(t.revoked_at),
        distinct: c.id,
        select: %{id: c.id, name: c.name}
      )
    )
  end

  @doc "Revoke this person's app connection, including all access and refresh tokens."
  def revoke_client(subject, client_id) do
    Repo.transaction(fn ->
      # Token issuance takes this same standard row lock. A concurrent refresh
      # cannot commit an unseen successor after disconnect has scanned its tokens.
      Repo.one(from(c in Client, where: c.id == ^client_id, lock: "FOR UPDATE"))
      tokens = Repo.all(from(t in Token, where: t.sub == ^subject and t.client_id == ^client_id))
      now = DateTime.utc_now()

      Repo.update_all(from(t in Token, where: t.sub == ^subject and t.client_id == ^client_id),
        set: [revoked_at: now, refresh_token_revoked_at: now]
      )

      # The database check above remains decisive even during cache invalidation.
      Enum.each(tokens, fn token ->
        token |> Boruta.Ecto.OauthMapper.to_oauth_schema() |> Boruta.Ecto.TokenStore.invalidate()
      end)

      :ok
    end)
  end
end

defmodule RegentOAuth.Test.Repo do
  @moduledoc "The test database's settings, which RegentOAuth.Repo copies."
  use Ecto.Repo, otp_app: :regent_oauth, adapter: Ecto.Adapters.Postgres

  def default_prefix, do: "regent_oauth_site"
end

defmodule RegentOAuth.Test.Site do
  @moduledoc "A site with one MCP resource; every account but `did:privy:gone` is active."
  @behaviour RegentOAuth

  @impl true
  def config do
    [
      enabled?: true,
      issuer: "http://localhost:4000",
      resource: "http://localhost:4000/mcp",
      scope: "regent.identity.manage",
      permission_description: "Keep a Regents identity for this app."
    ]
  end

  @impl true
  def repo, do: RegentOAuth.Test.Repo

  @impl true
  def current_subject(_conn), do: nil

  @impl true
  def active_subject?(subject), do: subject != "did:privy:gone"
end

defmodule RegentOAuth.Test.CreateTables do
  @moduledoc false
  use Ecto.Migration

  def up do
    RegentOAuth.Migration.up()
  end
end

defmodule RegentOAuth.Test.HashTokens do
  @moduledoc false
  use Ecto.Migration

  def up, do: RegentOAuth.Migration.V2.up()
end

defmodule RegentOAuth.Test.Schema do
  @moduledoc """
  Migrates a schema of the local test database to the given provider versions.
  Inside a sandboxed test the schema and everything in it is rolled back.
  """

  @migrations [{1, RegentOAuth.Test.CreateTables}, {2, RegentOAuth.Test.HashTokens}]

  # As a site runs them: its schema is the repo's `migration_default_prefix`.
  # Each schema keeps its own list of versions run.
  def migrate!(prefix, versions) do
    RegentOAuth.Repo.query!(~s(CREATE SCHEMA IF NOT EXISTS "#{prefix}"))
    config = Application.fetch_env!(:regent_oauth, RegentOAuth.Repo)

    Application.put_env(
      :regent_oauth,
      RegentOAuth.Repo,
      Keyword.merge(config,
        migration_default_prefix: prefix,
        migration_source: "#{prefix}_versions"
      )
    )

    try do
      Ecto.Migrator.run(
        RegentOAuth.Repo,
        Enum.filter(@migrations, fn {version, _} -> version in versions end),
        :up,
        all: true,
        log: false
      )
    after
      Application.put_env(:regent_oauth, RegentOAuth.Repo, config)
    end
  end
end

defmodule RegentOAuth.Test.Flow do
  @moduledoc "A public client that signs in through the real registration and token endpoints."
  import Plug.Test

  @verifier String.duplicate("v", 43)
  @redirect "https://claude.ai/api/mcp/auth_callback"

  def post(action, params) do
    conn(:post, "/oauth/#{action}")
    |> Map.put(:body_params, params)
    |> Map.put(:params, params)
    |> RegentOAuth.Protocol.call(action)
  end

  def client! do
    conn =
      post(:register, %{
        "client_name" => "Claude",
        "redirect_uris" => [@redirect],
        "token_endpoint_auth_method" => "none"
      })

    201 = conn.status
    Jason.decode!(conn.resp_body)["client_id"]
  end

  @doc "An authorization code for `subject`, made as Boruta makes one on consent."
  def code!(client_id, subject) do
    {:ok, code} =
      Boruta.CodesAdapter.create(%{
        client: Boruta.ClientsAdapter.get_client(client_id),
        resource_owner: %Boruta.Oauth.ResourceOwner{sub: subject},
        sub: subject,
        redirect_uri: @redirect,
        scope: "regent.identity.manage",
        state: "state",
        code_challenge: :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false),
        code_challenge_method: "S256"
      })

    :ok = RegentOAuth.bind_code(code.value)
    code.value
  end

  def exchange(client_id, code) do
    post(:token, %{
      "grant_type" => "authorization_code",
      "client_id" => client_id,
      "code" => code,
      "code_verifier" => @verifier,
      "redirect_uri" => @redirect,
      "resource" => RegentOAuth.resource()
    })
  end

  def refresh(client_id, refresh_token) do
    post(:token, %{
      "grant_type" => "refresh_token",
      "client_id" => client_id,
      "refresh_token" => refresh_token,
      "resource" => RegentOAuth.resource()
    })
  end

  @doc "Signs `subject` in with a new client; answers the client id and the token answer."
  def sign_in!(subject) do
    client_id = client!()
    conn = exchange(client_id, code!(client_id, subject))
    200 = conn.status
    {client_id, Jason.decode!(conn.resp_body)}
  end
end

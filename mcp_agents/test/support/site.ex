defmodule RegentMCPAgents.Test.Repo do
  @moduledoc "The test database's settings, which RegentOAuth.Repo copies."
  use Ecto.Repo, otp_app: :regent_mcp_agents, adapter: Ecto.Adapters.Postgres

  def default_prefix, do: "regent_mcp_agents_test"
end

defmodule RegentMCPAgents.Test.AgentsRepo do
  @moduledoc "The repository the site hands `RegentAgents`, with Ash's database functions."
  use AshPostgres.Repo, otp_app: :regent_mcp_agents, warn_on_missing_ash_functions?: false
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: ["ash-functions"]
end

defmodule RegentMCPAgents.Test.AgentsRepo.AshFunctions do
  @moduledoc "Installs Ash's database functions in the test database, as a site's migrations do."
  use Ecto.Migration

  def up do
    AshPostgres.MigrationGenerator.AshFunctions.install(nil)
    |> Code.eval_string([], __ENV__)
  end
end

defmodule RegentMCPAgents.Test.Accounts do
  @moduledoc "How the test site names a person's account in a check-in; every person has signed in here."
  def account(privy_user_id), do: %{display_name: "Person " <> privy_user_id}
end

defmodule RegentMCPAgents.Test.Site do
  @moduledoc "A site whose connector signs people in; every account is active."
  @behaviour RegentOAuth

  @impl true
  def config do
    [
      enabled?: true,
      issuer: "http://localhost:4000",
      resource: "http://localhost:4000/mcp",
      scope: "regent.identity.manage",
      permission_description: "Keep a Regents identity for this app.",
      additional_scopes: %{"patchbay.posts.write" => "Post free questions and replies."}
    ]
  end

  @impl true
  def repo, do: RegentMCPAgents.Test.Repo

  @impl true
  def current_subject(_conn), do: nil

  @impl true
  def active_subject?(_subject), do: true
end

defmodule RegentMCPAgents.Test.OAuthTables do
  @moduledoc false
  use Ecto.Migration

  def up do
    RegentOAuth.Migration.up()

    RegentOAuth.Migration.V2.up()
  end
end

defmodule RegentMCPAgents.Test.Limiter do
  @moduledoc "A request counter in the `RegentAgentAccess.RateLimit` admit shape; it records each key."
  use Agent

  def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def admit(key, limit, window) do
    count =
      Agent.get_and_update(
        __MODULE__,
        &Map.get_and_update(&1, key, fn n -> {(n || 0) + 1, (n || 0) + 1} end)
      )

    budget = %{limit: limit, remaining: max(limit - count, 0), reset: window, window: window}
    if count <= limit, do: {:ok, budget}, else: {:error, :rate_limited, budget}
  end

  def keys, do: Agent.get(__MODULE__, &Map.keys/1)

  @doc "Starts every key's count again."
  def reset, do: Agent.update(__MODULE__, fn _counts -> %{} end)
end

defmodule RegentMCPAgents.Case do
  @moduledoc "A connector request against the shared MCP address, in a rolled-back transaction."
  use ExUnit.CaseTemplate

  import Plug.Test

  using do
    quote do
      import RegentMCPAgents.Case
    end
  end

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(RegentOAuth.Repo, shared: true)
    agents = Ecto.Adapters.SQL.Sandbox.start_owner!(RegentMCPAgents.Test.AgentsRepo, shared: true)
    start_supervised!(RegentMCPAgents.Test.Limiter)
    Application.put_env(:regent_agents, :hosted_pairing, [:claude])

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(agents)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
      Application.delete_env(:regent_agents, :hosted_pairing)
    end)

    :ok
  end

  @opts RegentMCPAgents.Plug.init(
          app: :regent_mcp_agents,
          title: "Test Site",
          about: "Test Site, where people and their agents test things.",
          rate_limit: [
            policy: "mcp",
            limit: 3,
            window: 60,
            admit: &RegentMCPAgents.Test.Limiter.admit/3
          ]
        )

  @doc "A live access token for `subject`, issued to a newly registered app."
  def token!(subject), do: connect!(subject).access

  @doc """
  Connects a newly registered app for `subject`: its client id, and the plain
  access and refresh tokens it holds.
  """
  def connect!(subject) do
    register =
      conn(:post, "/oauth/register", %{
        "client_name" => "Claude",
        "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"]
      })
      |> RegentOAuth.Protocol.call(:register)

    client = Boruta.ClientsAdapter.get_client(Jason.decode!(register.resp_body)["client_id"])

    {:ok, token} =
      RegentOAuth.AccessTokens.create(
        %{client: client, sub: subject, scope: "regent.identity.manage"},
        refresh_token: true
      )

    %{client_id: client.id, access: token.value, refresh: token.refresh_token}
  end

  @doc "Refreshes an app's tokens through the token endpoint; answers the status and the answer."
  def refresh(client_id, refresh_token) do
    params = %{
      "grant_type" => "refresh_token",
      "client_id" => client_id,
      "refresh_token" => refresh_token,
      "resource" => RegentOAuth.resource()
    }

    conn =
      conn(:post, "/oauth/token")
      |> Map.merge(%{body_params: params, params: params})
      |> RegentOAuth.Protocol.call(:token)

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  @doc "The client and access token behind `token`, as the OAuth provider verifies it."
  def principal!(token) do
    {:ok, principal} = RegentOAuth.verify(token, RegentOAuth.resource())
    principal
  end

  @doc "A one-use pairing code made by `subject`'s account."
  def code!(subject),
    do: RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: subject}).code

  @doc "Calls one identity tool with `token` and answers its result."
  def tool(token, name, arguments \\ %{}) do
    # Each call starts a fresh budget; the budget has its own test.
    RegentMCPAgents.Test.Limiter.reset()
    json(mcp(rpc("tools/call", %{"name" => name, "arguments" => arguments}), token))["result"]
  end

  @doc "Sends one MCP request to the address, with `token` as its Bearer token when given."
  def mcp(body, token \\ nil, method \\ :post) do
    conn = conn(method, "/mcp", body)

    conn =
      if token,
        do: Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token),
        else: conn

    RegentMCPAgents.Plug.call(conn, @opts)
  end

  def rpc(method, params \\ %{}, id \\ 1),
    do: %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

  def json(conn), do: Jason.decode!(conn.resp_body)
end

# A local database of its own, made if missing. The OAuth provider's tables
# are migrated once; every test runs in a rolled-back transaction.
Application.put_env(:regent_mcp_agents, RegentMCPAgents.Test.Repo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: "regent_mcp_agents_test"
)

Application.put_env(:regent_mcp_agents, :config,
  enabled?: true,
  audience: "keyfleet",
  hosted_signer: [base_url: "https://siwa.test", key: String.duplicate("k", 32)]
)

_ = Ecto.Adapters.Postgres.storage_up(RegentMCPAgents.Test.Repo.config())
:ok = RegentOAuth.configure(RegentMCPAgents.Test.Site)

Application.put_env(
  :regent_oauth,
  RegentOAuth.Repo,
  Keyword.put(
    Application.fetch_env!(:regent_oauth, RegentOAuth.Repo),
    :pool,
    Ecto.Adapters.SQL.Sandbox
  )
)

{:ok, _} = RegentOAuth.Repo.start_link()
RegentOAuth.Repo.query!(~s(CREATE SCHEMA IF NOT EXISTS "regent_mcp_agents_test"))

Ecto.Migrator.run(
  RegentOAuth.Repo,
  [{1, RegentMCPAgents.Test.OAuthTables}, {2, RegentMCPAgents.Test.ClientDocuments}],
  :up,
  all: true,
  prefix: "regent_mcp_agents_test",
  log: false
)

Ecto.Adapters.SQL.Sandbox.mode(RegentOAuth.Repo, :manual)

# The site's agent records (`RegentAgents`), in the same database: pairing
# codes, paired agents and their check-ins, migrated as a site migrates them.
Application.put_env(
  :regent_mcp_agents,
  RegentMCPAgents.Test.AgentsRepo,
  Keyword.merge(RegentMCPAgents.Test.Repo.config(), pool: Ecto.Adapters.SQL.Sandbox, log: false)
)

Application.put_env(:ash, :default_string_length_count, :codepoints)

Application.put_env(:regent_agents, :repo, RegentMCPAgents.Test.AgentsRepo)
Application.put_env(:regent_agents, :account, {RegentMCPAgents.Test.Accounts, :account})

Application.put_env(:regent_agents, :allowed, %{
  "not_paired" => ["Read public pages."],
  "person_not_here" => ["Read public pages."],
  "paired" => ["Read public pages.", "Act for your person."]
})

{:ok, _} = RegentMCPAgents.Test.AgentsRepo.start_link()

Ecto.Migrator.run(
  RegentMCPAgents.Test.AgentsRepo,
  [{0, RegentMCPAgents.Test.AgentsRepo.AshFunctions}],
  :up,
  all: true,
  log: false
)

RegentAgents.Migrator.up(RegentMCPAgents.Test.AgentsRepo)
Ecto.Adapters.SQL.Sandbox.mode(RegentMCPAgents.Test.AgentsRepo, :manual)

ExUnit.start()

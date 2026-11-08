ExUnit.start()
config = RegentPoints.Repo.config()

unless Regex.match?(~r/^regent_points_test_[a-z0-9_]+$/, Keyword.fetch!(config, :database)),
  do: raise("refusing unowned database name")

# A new database each run, so its tables always have the shape this run creates.
:ok =
  case Ecto.Adapters.Postgres.storage_down(config) do
    :ok -> :ok
    {:error, :already_down} -> :ok
  end

:ok = Ecto.Adapters.Postgres.storage_up(config)

{:ok, _} = RegentPoints.Repo.start_link()
# Points broadcasts ledger changes, and queues its checks and awards on the site's Oban;
# here Oban runs each job as soon as it is queued.
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: RegentPoints.TestPubSub)
Application.put_env(:regent_points, :pubsub, RegentPoints.TestPubSub)
# Ash's database functions and Oban's table, as a site's own migrations install them.
defmodule RegentPoints.TestAshFunctions do
  use Ecto.Migration

  def up do
    AshPostgres.MigrationGenerator.AshFunctions.install(nil)
    |> Code.eval_string([], __ENV__)
  end
end

defmodule RegentPoints.TestOban do
  use Ecto.Migration
  def up, do: Oban.Migrations.up()
end

Ecto.Migrator.run(
  RegentPoints.Repo,
  [{0, RegentPoints.TestAshFunctions}, {1, RegentPoints.TestOban}],
  :up,
  all: true,
  log: false
)

{:ok, _} = Oban.start_link(repo: RegentPoints.Repo, testing: :inline)

# The host owns the canonical account table; Points only needs its Privy user and
# wallet columns.
for sql <- [
      "CREATE SCHEMA IF NOT EXISTS regent_names",
      """
      CREATE TABLE regent_names.platform_human_users
      (id bigserial PRIMARY KEY,
       privy_user_id text NOT NULL DEFAULT ('did:privy:' || gen_random_uuid()),
       wallet_address text, wallet_addresses text[])
      """,
      "CREATE SCHEMA IF NOT EXISTS regent_agents"
    ],
    do: RegentPoints.Repo.query!(sql)

# The shared record of accounts agents opened, from the agents library's own migration.
[{opened_accounts, _}] =
  :regent_agents
  |> Application.app_dir("priv/repo/migrations/20261108170000_opened_accounts.exs")
  |> Code.require_file()

Ecto.Migrator.run(RegentPoints.Repo, [{20_261_108_170_000, opened_accounts}], :up,
  all: true,
  log: false
)

RegentPoints.Migrator.up(RegentPoints.Repo)
Ecto.Adapters.SQL.Sandbox.mode(RegentPoints.Repo, :manual)

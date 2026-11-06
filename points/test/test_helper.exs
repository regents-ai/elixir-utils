# The races (test/review3/races_test.exs) run on their own database, by hand.
ExUnit.start(exclude: [:races])
config = RegentPoints.Repo.config()

unless Regex.match?(~r/^regent_points_test_[a-z0-9_]+$/, Keyword.fetch!(config, :database)),
  do: raise("refusing unowned database name")

case Ecto.Adapters.Postgres.storage_up(config) do
  :ok -> :ok
  {:error, :already_up} -> :ok
end

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

# The host owns the canonical account table; Points only needs its wallet columns.
for sql <- [
      "CREATE SCHEMA IF NOT EXISTS regent_names",
      """
      CREATE TABLE IF NOT EXISTS regent_names.platform_human_users
      (id bigserial PRIMARY KEY, wallet_address text, wallet_addresses text[])
      """
    ],
    do: RegentPoints.Repo.query!(sql)

RegentPoints.Migrator.up(RegentPoints.Repo)
Ecto.Adapters.SQL.Sandbox.mode(RegentPoints.Repo, :manual)

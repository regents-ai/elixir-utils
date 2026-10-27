ExUnit.start()
RegentCredits.TestChain.start()
name = Keyword.fetch!(RegentCredits.TestRepo.config(), :database)

unless Regex.match?(~r/^regent_credits_test[a-z0-9_]*$/, name),
  do: raise("refusing unowned database name")

{:ok, _} = RegentCredits.TestRepo.start_link()
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: RegentCredits.TestPubSub)

{:ok, _} =
  RegentCredits.TestRepo.config()
  |> Keyword.drop([:pool, :pool_size])
  |> Keyword.put(:name, RegentCredits.TestNotifications)
  |> Postgrex.Notifications.start_link()

{:ok, _} = RegentCredits.Listener.start_link([])
RegentAgents.Migrator.up(RegentCredits.TestRepo)
RegentCredits.Migrator.up(RegentCredits.TestRepo)
# A site runs the checks through its own Oban; tests run each job as it is queued.
RegentCredits.TestRepo.query!("CREATE SCHEMA IF NOT EXISTS test_oban")

Ecto.Migrator.up(RegentCredits.TestRepo, 1, RegentCredits.TestObanMigration,
  prefix: "test_oban",
  log: false
)

{:ok, _} = Oban.start_link(repo: RegentCredits.TestRepo, prefix: "test_oban", testing: :inline)

Ecto.Adapters.SQL.Sandbox.mode(RegentCredits.TestRepo, :manual)

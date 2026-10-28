# A local database of its own, made if missing. The provider's tables are
# migrated once into the test schema; every test runs in a rolled-back
# transaction.
Application.put_env(:regent_oauth, RegentOAuth.Test.Repo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: "regent_oauth_test"
)

_ = Ecto.Adapters.Postgres.storage_up(RegentOAuth.Test.Repo.config())
:ok = RegentOAuth.configure(RegentOAuth.Test.Site)

# The migrator's lock would wait on the one sandboxed connection a test holds.
Application.put_env(
  :regent_oauth,
  RegentOAuth.Repo,
  Application.fetch_env!(:regent_oauth, RegentOAuth.Repo)
  |> Keyword.merge(pool: Ecto.Adapters.SQL.Sandbox, migration_lock: false)
)

{:ok, _} = RegentOAuth.Repo.start_link()
RegentOAuth.Test.Schema.migrate!("regent_oauth_site", [1, 2])
Ecto.Adapters.SQL.Sandbox.mode(RegentOAuth.Repo, :manual)

ExUnit.start()

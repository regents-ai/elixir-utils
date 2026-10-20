import Config

config :regent_names, repo: RegentNames.TestRepo, privy_app_id: "names-test-app"

config :regent_names, RegentNames.TestRepo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: "regent_names_test_local#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 8

config :logger, level: :warning

# No resource here has notifiers; transactions report none.
config :ash, :missed_notifications, :ignore

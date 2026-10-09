import Config
config :regent_identity, repo: RegentIdentity.TestRepo

config :regent_identity, RegentIdentity.TestRepo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: "regent_identity_test_local#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 8

config :logger, level: :warning

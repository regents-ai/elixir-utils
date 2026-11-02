import Config

config :regent_points, RegentPoints.Repo,
  database: "regent_points_test_local#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning

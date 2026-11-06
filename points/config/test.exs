import Config

config :regent_points, RegentPoints.Repo,
  database: "regent_points_test_local#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # Wide enough for test/review3/races_test.exs to hold several real connections.
  pool_size: 14

config :logger, level: :warning

import Config
config :ash, default_string_length_count: :codepoints

config :regent_points,
  generate_migrations: true,
  ash_domains: [RegentPoints],
  repo: RegentPoints.Repo

config :regent_points, RegentPoints.Repo,
  hostname: "127.0.0.1",
  port: 5432,
  database: System.get_env("REGENT_POINTS_DATABASE") || "regent_points_dev",
  username: System.get_env("USER") || "postgres",
  pool_size: 5

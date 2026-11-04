import Config

if config_env() == :test do
  config :regent_http, ecto_repos: [RegentHttp.TestRepo]

  config :regent_http, RegentHttp.TestRepo,
    hostname: "127.0.0.1",
    port: 5432,
    username: System.get_env("USER"),
    database: "regent_http_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox

  config :error_tracker, repo: RegentHttp.TestRepo, otp_app: :regent_http

  config :logger, level: :warning
end

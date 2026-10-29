import Config

config :regent_agents,
  repo: RegentAgents.TestRepo,
  pubsub: RegentAgents.TestPubSub,
  notifications: RegentAgents.TestNotifications,
  account: {RegentAgents.Test.Site, :account},
  owned_account: {RegentAgents.Test.Site, :owned_account},
  allowed: %{
    "owner" => ["Read public pages.", "Act as your own account."],
    "not_paired" => ["Read public pages."],
    "person_not_here" => ["Read public pages."],
    "paired" => ["Read public pages.", "Act for your person."]
  },
  siwa: [url: "https://siwa.test", audience: "test"],
  req_options: [plug: {Req.Test, RegentAgents.Broker}]

config :regent_agents, RegentAgents.TestRepo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: "regent_agents_test_local#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 8

config :logger, level: :warning

# Every write inside a transaction runs in one Ash started (`Ash.transact/2`),
# so a notification left unsent fails the test instead of warning in production.
config :ash, :missed_notifications, :raise

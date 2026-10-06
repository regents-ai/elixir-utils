import Config

config :regent_credits,
  repo: RegentCredits.TestRepo,
  admins: ["did:privy:admin"],
  chain_client: RegentCredits.TestChain,
  chains: %{
    base: %{chain_id: 8453, name: "Base", rpc_url: "http://127.0.0.1:8545"},
    ethereum: %{chain_id: 1, name: "Ethereum", rpc_url: "http://127.0.0.1:8546"}
  }

config :regent_credits, RegentCredits.TestRepo,
  hostname: "127.0.0.1",
  port: 5432,
  username: System.get_env("USER"),
  database: "regent_credits_test_ledger#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 20,
  priv: "priv/repo"

config :logger, level: :warning

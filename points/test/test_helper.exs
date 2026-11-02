ExUnit.start()
config = RegentPoints.Repo.config()

unless Regex.match?(~r/^regent_points_test_[a-z0-9_]+$/, Keyword.fetch!(config, :database)),
  do: raise("refusing unowned database name")

case Ecto.Adapters.Postgres.storage_up(config) do
  :ok -> :ok
  {:error, :already_up} -> :ok
end

{:ok, _} = RegentPoints.Repo.start_link()

# The host owns the canonical account table; Points only needs its wallet columns.
for sql <- [
      "CREATE SCHEMA IF NOT EXISTS regent_names",
      """
      CREATE TABLE IF NOT EXISTS regent_names.platform_human_users
      (id bigserial PRIMARY KEY, wallet_address text, wallet_addresses text[])
      """
    ],
    do: RegentPoints.Repo.query!(sql)

RegentPoints.Migrator.up(RegentPoints.Repo)
Ecto.Adapters.SQL.Sandbox.mode(RegentPoints.Repo, :manual)

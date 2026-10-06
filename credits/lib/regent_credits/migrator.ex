defmodule RegentCredits.MigrationRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :regent_credits, adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_context, config),
    do: {:ok, Keyword.put(config, :migration_source, "schema_migrations")}
end

defmodule RegentCredits.Migrator do
  @moduledoc """
  Migrates the `regent_credits` schema over a dedicated connection, with its
  own migration ledger inside that schema. A site runs it locally; in
  production only Regents runs it, from its release preparation. Including
  the library never starts a repository or runs a migration.

  The first migration installs the `money_with_currency` type the ledger
  stores amounts in, database-wide in `public`, with its operators.
  """

  @spec up(module()) :: :ok
  def up(repo) do
    options =
      repo.config()
      |> Keyword.drop([:name, :telemetry_prefix, :default_prefix, :migration_default_prefix])
      |> Keyword.merge(
        migration_source: "schema_migrations",
        pool: DBConnection.ConnectionPool,
        pool_size: 2
      )

    case RegentCredits.MigrationRepo.start_link(options) do
      {:ok, pid} ->
        try do
          Ecto.Adapters.SQL.query!(
            RegentCredits.MigrationRepo,
            "CREATE SCHEMA IF NOT EXISTS regent_credits",
            []
          )

          Ecto.Migrator.run(
            RegentCredits.MigrationRepo,
            Application.app_dir(:regent_credits, "priv/repo/migrations"),
            :up,
            all: true,
            prefix: "regent_credits"
          )

          :ok
        after
          Supervisor.stop(pid)
        end

      {:error, _reason} ->
        raise "Unable to start the dedicated Credits migration connection"
    end
  end
end

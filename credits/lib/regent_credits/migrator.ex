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

  @doc "Checks episode-bound grant prerequisites without applying shared migrations."
  @spec require_pairing_grants!(module()) :: :ok
  def require_pairing_grants!(repo) do
    %{rows: [[ready?]]} =
      Ecto.Adapters.SQL.query!(repo, """
      SELECT
        (SELECT count(*) = 2 FROM pg_catalog.pg_attribute a
          JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'regent_credits' AND c.relname IN ('holds', 'agent_permissions')
            AND a.attname = 'pairing_id' AND NOT a.attisdropped)
        AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
          JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'regent_agents' AND c.relname = 'paired_agents'
            AND t.tgname = 'revoke_credit_grant'
            AND NOT t.tgisinternal AND t.tgenabled IN ('O', 'A'))
        AND EXISTS (SELECT 1 FROM pg_catalog.pg_constraint con
          JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'regent_credits' AND c.relname = 'agent_permissions'
            AND con.conname = 'enabled_requires_pairing' AND con.convalidated
            AND con.contype = 'c')
      """)

    unless ready?,
      do:
        raise(
          "Signed agent access requires the separately approved shared Credits pairing-grant migration before deployment"
        )

    :ok
  end

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

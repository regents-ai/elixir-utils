defmodule RegentNames.TestRepo do
  @moduledoc "The repository a site hands the library, with Ash's database functions."
  use AshPostgres.Repo, otp_app: :regent_names, warn_on_missing_ash_functions?: false
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: ["ash-functions"]
end

defmodule RegentNames.TestRepo.AshFunctions do
  @moduledoc "Installs Ash's database functions in the test database, as a site's migrations do."
  use Ecto.Migration

  def up do
    AshPostgres.MigrationGenerator.AshFunctions.install(nil)
    |> Code.eval_string([], __ENV__)
  end
end

defmodule RegentNames.TestRepo.Tables do
  @moduledoc """
  The imported names tables, as they stand on the shared database. The library
  never migrates them; the test database gets them here.
  """
  use Ecto.Migration

  def up do
    execute("CREATE SCHEMA IF NOT EXISTS regent_names")

    # Claims made on a site are numbered far above every synthetic row.
    execute("CREATE SEQUENCE regent_names.basenames_mints_id_seq START WITH 1000000000")

    execute("""
    CREATE TABLE regent_names.basenames_mints (
      id bigint PRIMARY KEY DEFAULT nextval('regent_names.basenames_mints_id_seq'),
      parent_node varchar(66) NOT NULL, parent_name text NOT NULL,
      label varchar(63) NOT NULL, fqdn text NOT NULL, node varchar(66) NOT NULL,
      ens_fqdn text, ens_node varchar(66), owner_address varchar(42) NOT NULL,
      tx_hash varchar(66), ens_tx_hash varchar(66), ens_assigned_at timestamptz,
      payment_tx_hash varchar(66), payment_chain_id integer, price_wei bigint,
      is_free boolean NOT NULL DEFAULT false, is_in_use boolean NOT NULL DEFAULT false,
      created_at timestamptz NOT NULL DEFAULT now(),
      claim_status varchar(255) NOT NULL DEFAULT 'reserved',
      upgrade_tx_hash varchar(255), upgraded_at timestamp,
      formation_agent_slug varchar(255), attached_agent_slug varchar(255)
    )
    """)

    execute("""
    CREATE UNIQUE INDEX basenames_mints_node_unique ON regent_names.basenames_mints (node)
    """)

    execute("""
    CREATE TABLE regent_names.basenames_mint_allowances (
      parent_node varchar(66) NOT NULL, parent_name text NOT NULL, address varchar(42) NOT NULL,
      snapshot_block_number integer NOT NULL, snapshot_total integer NOT NULL,
      free_mints_used integer NOT NULL DEFAULT 0,
      created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (parent_node, address)
    )
    """)

    execute("""
    CREATE TABLE regent_names.basenames_payment_credits (
      id bigserial PRIMARY KEY, parent_node varchar(66) NOT NULL, parent_name text NOT NULL,
      address varchar(42) NOT NULL, payment_tx_hash varchar(66) NOT NULL,
      payment_chain_id integer, price_wei bigint NOT NULL, consumed_at timestamptz,
      consumed_node varchar(66), consumed_fqdn text,
      created_at timestamptz NOT NULL DEFAULT now()
    )
    """)
  end
end

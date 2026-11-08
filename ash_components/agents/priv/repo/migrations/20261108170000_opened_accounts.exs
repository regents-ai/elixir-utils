defmodule RegentAgents.Migrations.OpenedAccounts do
  @moduledoc """
  Adds `regent_agents.opened_accounts` (`RegentAgents.OpenedAccount`): the
  accounts agents opened for themselves. It only creates a table and its index;
  no existing table, row or column changes, and nothing else is locked. Its
  locks wait at most five seconds, then it fails rather than holding up a site.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    create table(:opened_accounts, prefix: "regent_agents", primary_key: false) do
      add(:privy_user_id, :text, null: false, primary_key: true)
      add(:wallet, :text, null: false)

      add(:opened_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    # A site finds the account an agent's wallet opened by that wallet.
    create index(:opened_accounts, [:wallet], prefix: "regent_agents")
  end

  def down do
    drop(table(:opened_accounts, prefix: "regent_agents"))
  end
end

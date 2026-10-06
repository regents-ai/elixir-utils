defmodule RegentCredits.Repo.Migrations.OpenRegentAccounts do
  @moduledoc """
  Opens the four Regent accounts every operation moves Credits from or to:
  purchased and given Credits come from `regent_purchases` and `regent_gifts`,
  revenue goes to `regent_revenue`, refunded Credits to `regent_refunds`.
  They exist before any site runs, so no operation ever opens one.
  """
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO regent_credits.accounts (identifier, currency)
    VALUES ('regent_purchases', 'XRC'), ('regent_gifts', 'XRC'),
           ('regent_revenue', 'XRC'), ('regent_refunds', 'XRC')
    """)
  end

  def down do
    execute("""
    DELETE FROM regent_credits.accounts
    WHERE identifier IN ('regent_purchases', 'regent_gifts', 'regent_revenue', 'regent_refunds')
    """)
  end
end

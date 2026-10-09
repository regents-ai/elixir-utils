defmodule RegentCredits.Repo.Migrations.OpenBaseDepositCursor do
  @moduledoc """
  Starts reading Base's Credits deposits at block 52,227,727, the first block
  of 6 October 2026 (UTC). The Credits deposit tag first existed later that
  day, so every Credits deposit is at or after it.
  """
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO regent_credits.deposit_cursors (chain, next_block)
    VALUES ('base', 52227727)
    """)
  end

  def down do
    execute("DELETE FROM regent_credits.deposit_cursors WHERE chain = 'base'")
  end
end

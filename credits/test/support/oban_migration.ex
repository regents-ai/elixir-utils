defmodule RegentCredits.TestObanMigration do
  @moduledoc "The jobs table of the test site's Oban, in a schema of its own."
  use Ecto.Migration

  def up, do: Oban.Migration.up(prefix: "test_oban")
  def down, do: Oban.Migration.down(prefix: "test_oban")
end

defmodule RegentCredits.TestRepo do
  @moduledoc """
  The repository a site hands the library, set up as a site's own: with Ash's
  database functions and the money type the ledger stores amounts in.
  """
  use AshPostgres.Repo, otp_app: :regent_credits, warn_on_missing_ash_functions?: false
  def min_pg_version, do: %Version{major: 17, minor: 0, patch: 0}
  def installed_extensions, do: ["ash-functions", AshMoney.AshPostgresExtension]
end

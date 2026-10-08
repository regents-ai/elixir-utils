defmodule RegentPoints.Repo do
  @moduledoc false
  use AshPostgres.Repo, otp_app: :regent_points
  def migrate_extensions?, do: false
  def installed_extensions, do: ["ash-functions"]
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
end

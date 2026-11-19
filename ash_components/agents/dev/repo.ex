defmodule RegentAgents.Repo do
  @moduledoc false
  use AshPostgres.Repo, otp_app: :regent_agents, warn_on_missing_ash_functions?: false
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: ["ash-functions"]
end

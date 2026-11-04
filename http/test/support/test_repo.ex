defmodule RegentHttp.TestRepo do
  use Ecto.Repo, otp_app: :regent_http, adapter: Ecto.Adapters.Postgres
end

defmodule RegentHttp.TestErrorTrackerMigration do
  use Ecto.Migration

  def up, do: ErrorTracker.Migration.up()
  def down, do: ErrorTracker.Migration.down()
end

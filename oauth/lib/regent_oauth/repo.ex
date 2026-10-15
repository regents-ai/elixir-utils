defmodule RegentOAuth.Repo do
  @moduledoc "Boruta's store in the owning site's schema, with SQL parameter logging disabled."
  use Ecto.Repo, otp_app: :regent_oauth, adapter: Ecto.Adapters.Postgres

  @impl true
  def default_options(_operation) do
    [prefix: Application.fetch_env!(:regent_oauth, :prefix), log: false, telemetry_event: nil]
  end
end

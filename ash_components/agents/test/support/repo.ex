defmodule RegentAgents.TestRepo do
  @moduledoc "The repository a site hands the library, with Ash's database functions."
  use AshPostgres.Repo, otp_app: :regent_agents, warn_on_missing_ash_functions?: false
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  def installed_extensions, do: ["ash-functions"]
end

defmodule RegentAgents.TestRepo.AshFunctions do
  @moduledoc "Installs Ash's database functions in the test database, as a site's migrations do."
  use Ecto.Migration

  def up do
    AshPostgres.MigrationGenerator.AshFunctions.install(nil)
    |> Code.eval_string([], __ENV__)
  end
end

defmodule RegentAgents.Test.Site do
  @moduledoc """
  How the test site names a person's account in a check-in, and the account an
  agent owns; one person has never signed in here, and one wallet owns an account.
  """
  def account("did:privy:away"), do: nil
  def account(privy_user_id), do: %{display_name: "Person " <> privy_user_id}

  def owned_account("0x3333333333333333333333333333333333333333"),
    do: %{display_name: "Agent account"}

  def owned_account(_wallet), do: nil
end

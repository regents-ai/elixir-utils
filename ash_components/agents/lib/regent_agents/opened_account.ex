defmodule RegentAgents.OpenedAccount do
  @moduledoc """
  An account an agent opened for itself on a Regent site: the agent's own
  signing wallet (lowercase) and the Privy user that opening signed in to, one
  per wallet. Accounts are shared by every site, so this record is too: each
  site reads it to know an account is an agent's own (`whoami`'s `owner`) and
  gives such an account none of the one-time Points awards a script could
  collect by opening accounts.

  Only a site's opening writes it, and only a site reads it, each with its own
  system actor (`role: :system`); no person or agent reaches it directly.
  """

  use Ash.Resource,
    otp_app: :regent_agents,
    domain: RegentAgents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentAgents.repo/2
    schema "regent_agents"
    table "opened_accounts"
    migrate? false
  end

  attributes do
    attribute :wallet, :string, primary_key?: true, allow_nil?: false
    attribute :privy_user_id, :string, allow_nil?: false, sensitive?: true
    create_timestamp :opened_at
  end

  actions do
    read :read do
      primary? true
    end

    read :by_wallet do
      get? true
      argument :wallet, :string, allow_nil?: false
      filter expr(wallet == ^arg(:wallet))
    end

    # Opening again from a wallet whose account moved names the new one.
    create :record do
      accept [:wallet, :privy_user_id]
      upsert? true
      upsert_fields [:privy_user_id]
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end
end

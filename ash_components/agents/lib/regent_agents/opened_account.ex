defmodule RegentAgents.OpenedAccount do
  @moduledoc """
  An account an agent opened for itself on a Regent site: the Privy user that
  opening signed in to, and the agent's own signing wallet (lowercase). One per
  Privy user, and never removed: an account an agent opened stays the agent's,
  whatever its wallet does later. Accounts are shared by every site, so this
  record is too: each site reads it to know an account is an agent's own
  (`whoami`'s `owner`) and gives such an account none of the one-time Points
  awards a script could collect by opening accounts.

  A site writes it when an agent opens its account, and when someone signs in to
  a Privy user an agent's opening made (Privy's `regent_agent` metadata names the
  wallet); only a site reads it. Each uses its own system actor (`role: :system`);
  no person or agent reaches it directly.
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
    attribute :privy_user_id, :string, primary_key?: true, allow_nil?: false, sensitive?: true
    attribute :wallet, :string, allow_nil?: false
    create_timestamp :opened_at
  end

  actions do
    read :read do
      primary? true
    end

    # The same Privy user recorded again names the wallet it signs in with now.
    create :record do
      accept [:wallet, :privy_user_id]
      upsert? true
      upsert_fields [:wallet]
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end
end

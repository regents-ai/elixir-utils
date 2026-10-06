defmodule RegentCredits.Wallet do
  @moduledoc """
  A wallet address the site's sign-in verified for a Privy account, as of
  that account's last `attach_wallets`. Credits given or paid to the address
  then go straight to the account; an address no account has shown keeps
  them under itself until one does.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "wallets"

    custom_indexes do
      index [:privy_user_id]
    end
  end

  attributes do
    # A lowercase wallet address.
    attribute :address, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :privy_user_id, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read, :destroy]

    # A wallet moved to another account belongs to that account from now on.
    create :remember do
      accept [:address, :privy_user_id]
      upsert? true
      upsert_fields [:privy_user_id, :updated_at]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end
  end
end

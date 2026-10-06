defmodule RegentCredits.Gift do
  @moduledoc """
  Credits an admin gave: to a Privy account, or to a wallet address. Given
  Credits never expire and are never refunded.

  A gift to a wallet address goes straight to the Privy account that last
  showed that wallet at sign-in (`attach_wallets`). A gift to an address no
  account has shown waits under it until one does, as does a bounty paid to
  such an address.

  One gift is named by the admin's `key` (one per send) and its recipient,
  so sending the same gift again gives nothing twice.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentCredits.Gifts

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "gifts"
  end

  attributes do
    uuid_primary_key :id
    attribute :key, :string, allow_nil?: false, public?: true

    # A Privy account id, or a lowercase wallet address.
    attribute :to, :string, allow_nil?: false, public?: true

    attribute :amount, :decimal, allow_nil?: false, public?: true
    attribute :note, :string, public?: true
    attribute :given_by, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :key_to, [:key, :to]
  end

  actions do
    defaults [:read]

    create :record do
      accept [:key, :to, :amount, :note, :given_by]
    end

    action :give, {:array, :struct} do
      description "Gives `amount` Credits to each Privy account id or wallet address in `to`."
      constraints items: [instance_of: __MODULE__]
      transaction? true
      argument :key, :string, allow_nil?: false
      argument :to, {:array, :string}, allow_nil?: false, constraints: [min_length: 1]
      argument :amount, :decimal, allow_nil?: false
      argument :note, :string
      run fn input, context -> Gifts.give(input.arguments, context.actor) end
    end

    action :attach_wallets, :decimal do
      description """
      Records that the Privy account holds exactly these wallet addresses,
      moves Credits waiting under them to it, and answers with how much
      moved. The site calls it at sign-in and when a wallet is linked, with
      the wallets Privy says the account holds; Credits later given or paid
      to those wallets go straight to the account.
      """

      transaction? true
      argument :privy_user_id, :string, allow_nil?: false
      argument :wallets, {:array, :string}, allow_nil?: false
      run fn input, context -> Gifts.attach_wallets(input.arguments, context.actor) end
    end
  end

  policies do
    policy action(:give) do
      authorize_if RegentCredits.Checks.Admin
    end

    policy action(:attach_wallets) do
      authorize_if actor_attribute_equals(:role, :site)
    end

    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
      authorize_if expr(to == ^actor(:privy_user_id))
    end
  end
end

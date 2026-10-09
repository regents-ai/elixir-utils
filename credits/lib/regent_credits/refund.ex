defmodule RegentCredits.Refund do
  @moduledoc """
  A refund of one purchase, allowed only while the account has never used
  Credits (`RegentCredits.FirstUse`). Given Credits are never refunded.

  An admin starts it (`start`), which takes the purchase's Credits out of
  the account, then sends the USDC from the Treasury Safe to the wallet that
  paid, on the chain it paid on, and closes it with that transaction
  (`close`), which the library checks before marking the refund sent.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentCredits.Refunds

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "refunds"
  end

  attributes do
    uuid_primary_key :id
    attribute :purchase_id, :uuid, allow_nil?: false, public?: true
    attribute :privy_user_id, :string, allow_nil?: false, public?: true

    # Where the USDC goes back to: the wallet and chain that paid.
    attribute :wallet, :string, allow_nil?: false, public?: true

    attribute :chain, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:base, :ethereum]
    end

    attribute :amount, :decimal, allow_nil?: false, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :locked
      public? true
      constraints one_of: [:locked, :sent]
    end

    attribute :tx_hash, :string, public?: true
    attribute :started_by, :string, allow_nil?: false, public?: true
    attribute :sent_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :purchase, [:purchase_id]
    identity :transaction, [:chain, :tx_hash]
  end

  actions do
    defaults [:read]

    create :record do
      accept [:purchase_id, :privy_user_id, :wallet, :chain, :amount, :started_by]
    end

    update :sent do
      accept [:tx_hash]
      validate attribute_equals(:status, :locked)
      change set_attribute(:status, :sent)
      change set_attribute(:sent_at, &DateTime.utc_now/0)
    end

    action :start, :struct do
      description "Takes a purchase's Credits back out of the account so its USDC can be returned."
      constraints instance_of: __MODULE__
      transaction? true
      argument :purchase_id, :uuid, allow_nil?: false
      run fn input, context -> Refunds.start(input.arguments.purchase_id, context.actor) end
    end

    action :close, :struct do
      description "Checks the Treasury Safe's USDC transfer back to the wallet, then marks the refund sent."
      constraints instance_of: __MODULE__
      argument :id, :uuid, allow_nil?: false
      argument :tx_hash, :string, allow_nil?: false
      run fn input, _context -> Refunds.close(input.arguments) end
    end
  end

  policies do
    policy action([:start, :close]) do
      authorize_if RegentCredits.Checks.Admin
    end

    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end
  end
end

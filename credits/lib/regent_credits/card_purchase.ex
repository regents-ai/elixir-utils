defmodule RegentCredits.CardPurchase do
  @moduledoc """
  One purchase of Credits by card or Link, paid through Stripe Checkout with the
  Payment Element on the site's own page (`RegentCredits.Stripe`).

  `start` opens the Checkout Session for whole dollars of Credits, $5 to $500,
  with Stripe's card fee added on top (2.9% + 30 cents, so the Credits arrive
  whole), and answers the `client_secret` the page mounts the Payment Element
  with. Every press is its own purchase.

  The Credits arrive once, as purchased Credits, when Stripe says the session is
  paid: from the site's webhook (`notice`), which carries the signed session, or
  from the page after the payment confirms (`settle`), which reads the session
  from Stripe. Whichever comes first credits; the other finds it credited.

  A refund takes its share of the Credits back out of the account, and a dispute
  takes back the rest, even when that leaves the balance below zero (Sean, 27
  October 2026). While a person's Credits are below zero they cannot spend, and
  cannot start another card purchase.

  With Stripe's test keys, only Credits admins can start one: a test card adds
  real Credits to the shared ledger.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentCredits.CardPurchases

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "card_purchases"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :privy_user_id, :string, allow_nil?: false, public?: true

    # The site the purchase was started on, in its own short code.
    attribute :site, :string, allow_nil?: false, public?: true

    attribute :credits, :integer do
      allow_nil? false
      public? true
      constraints min: 5, max: 500
    end

    # What the card was charged, in US cents: the Credits and the card fee.
    attribute :fee_cents, :integer, allow_nil?: false, public?: true
    attribute :total_cents, :integer, allow_nil?: false, public?: true

    attribute :session_id, :string, allow_nil?: false, public?: true
    attribute :payment_intent_id, :string, public?: true

    # Paid with Stripe's test keys.
    attribute :livemode, :boolean, allow_nil?: false, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :open
      public? true
      constraints one_of: [:open, :credited]
    end

    # Credits taken back out by refunds and a dispute, to the millionth.
    attribute :taken_back, :decimal do
      allow_nil? false
      default 0
      public? true
      constraints min: 0
    end

    attribute :credited_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :session, [:session_id]
    identity :payment_intent, [:payment_intent_id]
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, required?: false
    end

    create :record do
      accept [
        :id,
        :privy_user_id,
        :site,
        :credits,
        :fee_cents,
        :total_cents,
        :session_id,
        :livemode
      ]
    end

    update :credited do
      accept [:payment_intent_id]
      change filter(expr(status == :open))
      change set_attribute(:status, :credited)
      change set_attribute(:credited_at, &DateTime.utc_now/0)

      emit RegentCredits.Signals, :card_purchase_credited,
        fields: [purchase_id: :id, privy_user_id: :privy_user_id]
    end

    update :took_back do
      accept [:taken_back]
      change filter(expr(status == :credited))
    end

    # Not in a transaction: it opens the Checkout Session at Stripe first.
    action :start, :map do
      description "Opens a card or Link payment for Credits and answers what the page needs to show it."
      argument :privy_user_id, :string, allow_nil?: false
      argument :credits, :integer, allow_nil?: false, constraints: [min: 5, max: 500]
      argument :return_url, :string, allow_nil?: false, constraints: [max_length: 2_048]
      run fn input, context -> CardPurchases.start(input.arguments, context.actor) end
    end

    action :settle, :struct do
      description "Reads the payment from Stripe and adds its Credits once it is paid."
      constraints instance_of: __MODULE__
      argument :session_id, :string, allow_nil?: false, constraints: [max_length: 255]
      run fn input, context -> CardPurchases.settle(input.arguments.session_id, context.actor) end
    end

    action :notice do
      description "Handles a webhook notice from Stripe once its signature checks."
      argument :payload, :string, allow_nil?: false, constraints: [trim?: false]
      argument :signature, :string, allow_nil?: false, constraints: [max_length: 2_048]
      run fn input, _context -> CardPurchases.notice(input.arguments) end
    end
  end

  policies do
    policy action(:start) do
      authorize_if RegentCredits.Checks.OwnCredits
    end

    policy action(:start) do
      authorize_if RegentCredits.Checks.CardTesting
    end

    # Ownership is the read below: a person settles only their own purchase.
    policy action(:settle) do
      authorize_if actor_attribute_equals(:role, :person)
    end

    # The signature proves the notice; the site's own code passes it on.
    policy action(:notice) do
      authorize_if actor_attribute_equals(:role, :site)
    end

    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end
  end
end

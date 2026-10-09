defmodule RegentCredits.Hold do
  @moduledoc """
  Credits set aside for one spend, named by the site's own `key` (a bid id, a
  fix id, a post id). A hold takes given Credits first, then purchased ones,
  and remembers how much of each, so whatever comes back returns as the same
  kind.

  A hold is closed exactly once, by one of:

    * `give_back`: all of it returns (a lost bid, a failed fix).
    * `charge`: all of it becomes revenue (a delivered fix).
    * `carry_over`: the same Credits now pay for a new hold under a new key,
      with no new charge (a waiting Offer bid that starts showing).
    * `settle`: an Offer ends; `returned + used + forfeited` equals the hold.
    * `pay_bounty`: a chosen answer's owner gets 90% as given Credits, 10% is
      revenue.
    * `take_back`: an unanswered bounty returns to the asker at the same
      90/10, as given Credits.

  Repeating an operation with the same details answers with the first result;
  the same key with other details is refused.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentCredits.Holds

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "holds"
  end

  attributes do
    uuid_primary_key :id

    attribute :site, :string, allow_nil?: false, public?: true
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :privy_user_id, :string, allow_nil?: false, public?: true

    # What the Credits are for, in the site's words: "fix", "priority_post", "offer_bid".
    attribute :purpose, :string, allow_nil?: false, public?: true

    # The agent that spent, when an agent did.
    attribute :agent_address, :string, public?: true
    attribute :pairing_id, :uuid, public?: true

    attribute :amount, :decimal, allow_nil?: false, public?: true
    attribute :given, :decimal, allow_nil?: false, public?: true
    attribute :purchased, :decimal, allow_nil?: false, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :held
      public? true

      constraints one_of: [
                    :held,
                    :given_back,
                    :charged,
                    :carried_over,
                    :settled,
                    :bounty_paid,
                    :taken_back
                  ]
    end

    # How the hold closed: what came back, what was used and what was forfeited.
    attribute :returned, :decimal, public?: true
    attribute :used, :decimal, public?: true
    attribute :forfeited, :decimal, public?: true

    # The key of the hold these Credits were carried over to.
    attribute :carried_to, :string, public?: true

    # Who received a bounty: a Privy account id or a wallet address.
    attribute :paid_to, :string, public?: true

    attribute :reason, :string, public?: true
    attribute :closed_at, :utc_datetime_usec, public?: true

    # When these Credits were first set aside. A carry keeps it, so an agent's
    # daily limit counts a carried bid once, on the day it was first held.
    attribute :held_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :site_key, [:site, :key]
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :site,
        :key,
        :privy_user_id,
        :purpose,
        :agent_address,
        :pairing_id,
        :amount,
        :given,
        :purchased,
        :held_at
      ]
    end

    update :close do
      accept [
        :status,
        :returned,
        :used,
        :forfeited,
        :carried_to,
        :paid_to,
        :reason,
        :closed_at
      ]
    end

    action :hold, :struct do
      description "Sets aside `amount` of the person's Credits under `key`."
      constraints instance_of: __MODULE__
      transaction? true
      argument :key, :string, allow_nil?: false
      argument :privy_user_id, :string, allow_nil?: false
      argument :amount, :decimal, allow_nil?: false
      argument :purpose, :string, allow_nil?: false
      run fn input, context -> Holds.hold(input.arguments, context.actor) end
    end

    action :give_back, :struct do
      constraints instance_of: __MODULE__
      transaction? true
      argument :key, :string, allow_nil?: false
      argument :reason, :string, allow_nil?: false
      run fn input, context -> Holds.give_back(input.arguments, context.actor) end
    end

    action :charge, :struct do
      constraints instance_of: __MODULE__
      transaction? true
      argument :key, :string, allow_nil?: false
      run fn input, context -> Holds.charge(input.arguments, context.actor) end
    end

    action :carry_over, :struct do
      constraints instance_of: __MODULE__
      transaction? true
      argument :key, :string, allow_nil?: false
      argument :to_key, :string, allow_nil?: false
      argument :purpose, :string, allow_nil?: false
      run fn input, context -> Holds.carry_over(input.arguments, context.actor) end
    end

    action :settle, :struct do
      constraints instance_of: __MODULE__
      transaction? true
      argument :key, :string, allow_nil?: false
      argument :returned, :decimal, allow_nil?: false
      argument :used, :decimal, allow_nil?: false
      argument :forfeited, :decimal, allow_nil?: false
      argument :reason, :string
      run fn input, context -> Holds.settle(input.arguments, context.actor) end
    end

    action :pay_bounty, :struct do
      description "Pays a bounty to an answer's owner: a Privy account id, or a wallet address."
      constraints instance_of: __MODULE__
      transaction? true
      argument :key, :string, allow_nil?: false
      argument :to, :string, allow_nil?: false
      run fn input, context -> Holds.pay_bounty(input.arguments, context.actor) end
    end

    action :take_back, :struct do
      constraints instance_of: __MODULE__
      transaction? true
      argument :key, :string, allow_nil?: false
      run fn input, context -> Holds.take_back(input.arguments, context.actor) end
    end

    action :lock_holds do
      description "Locks every account closing these holds or holding for these people moves."
      transaction? true
      argument :keys, {:array, :string}, allow_nil?: false
      argument :privy_user_ids, {:array, :string}, allow_nil?: false
      run fn input, context -> Holds.lock_holds(input.arguments, context.actor) end
    end
  end

  policies do
    policy action(:hold) do
      authorize_if {RegentCredits.Checks.OwnCredits, roles: [:person, :agent]}
    end

    policy action([
             :give_back,
             :charge,
             :carry_over,
             :settle,
             :pay_bounty,
             :take_back,
             :lock_holds
           ]) do
      authorize_if actor_attribute_equals(:role, :site)
    end

    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
      authorize_if expr(site == ^actor(:site) and ^actor(:role) == :site)
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end
  end
end

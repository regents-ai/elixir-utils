defmodule RegentCredits.Purchase do
  @moduledoc """
  One wallet payment for Credits: a sent transaction a person's page reported.
  Every press is its own purchase, so a second press of Buy that also lands
  buys Credits twice.

  The purchase is checked at the latest block (`check`), by the page every
  two seconds while it waits and by the site's Oban once a minute until it
  is decided:

    * Base: credited when the receipt shows the deposit went through.
    * Ethereum: credited once the block holding it has 12 blocks on top and
      a later read still finds it in that same block.
    * Failed when it reverted, is not the purchase it claims to be, or is
      still unknown to the chain a day after it was reported.

  A person reports only payments sent from the wallets their sign-in
  verified (`RegentCredits.Checks.OwnWallet`), and a transaction credits at
  most once, whoever reports it.

  The site runs the checks: its Oban has a `:regent_credits` queue and its
  AshOban configuration lists the `RegentCredits` domain.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias RegentCredits.Purchases

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "purchases"

    identity_wheres_to_sql credited: "status = 'credited'"
  end

  oban do
    triggers do
      trigger :check do
        action :check_due
        where expr(status == :checking)
        scheduler_cron "* * * * *"
        queue :regent_credits
        max_attempts 3
        worker_module_name RegentCredits.Purchase.AshOban.Worker.Check
        scheduler_module_name RegentCredits.Purchase.AshOban.Scheduler.Check
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :privy_user_id, :string, allow_nil?: false, public?: true

    # The signed-in wallet that sent it.
    attribute :wallet, :string, allow_nil?: false, public?: true

    attribute :chain, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:base, :ethereum]
    end

    # Whole dollars, $5 to $500.
    attribute :amount, :integer do
      allow_nil? false
      public? true
      constraints min: 5, max: 500
    end

    # The purchase number the panel built the steps with.
    attribute :number, :uuid, allow_nil?: false, public?: true
    attribute :tx_hash, :string, allow_nil?: false, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :checking
      public? true
      constraints one_of: [:checking, :credited, :failed]
    end

    attribute :reason, :string, public?: true

    # Ethereum: the block the transaction was last seen in.
    attribute :block_number, :integer, public?: true
    attribute :block_hash, :string, public?: true

    attribute :credited_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :report, [:privy_user_id, :chain, :tx_hash]
    identity :credited, [:chain, :tx_hash], where: expr(status == :credited)
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, required?: false
    end

    create :record do
      accept [:privy_user_id, :wallet, :chain, :amount, :number, :tx_hash]
    end

    update :seen do
      accept [:block_number, :block_hash]
    end

    update :finish do
      accept [:status, :reason, :credited_at]
    end

    action :report, :struct do
      description "Records a purchase the person's wallet sent."
      constraints instance_of: __MODULE__
      transaction? true
      argument :privy_user_id, :string, allow_nil?: false
      argument :wallet, :string, allow_nil?: false
      argument :chain, :atom, allow_nil?: false, constraints: [one_of: [:base, :ethereum]]
      argument :amount, :integer, allow_nil?: false, constraints: [min: 5, max: 500]
      argument :number, :uuid, allow_nil?: false
      argument :tx_hash, :string, allow_nil?: false
      run fn input, _context -> Purchases.report(input.arguments) end
    end

    action :check, :struct do
      description "Reads the purchase's transaction and credits it once it counts."
      constraints instance_of: __MODULE__
      argument :id, :uuid, allow_nil?: false
      run fn input, _context -> Purchases.check(input.arguments.id) end
    end

    action :check_due do
      description "The Oban check of a purchase still being checked."
      argument :primary_key, :map, allow_nil?: false

      run fn input, _context ->
        with {:ok, _purchase} <- Purchases.check(input.arguments.primary_key["id"]), do: :ok
      end
    end

    action :credit, :struct do
      constraints instance_of: __MODULE__
      transaction? true
      argument :id, :uuid, allow_nil?: false
      run fn input, _context -> Purchases.credit(input.arguments.id) end
    end
  end

  policies do
    policy action(:report) do
      authorize_if RegentCredits.Checks.OwnCredits
    end

    policy action(:report) do
      authorize_if RegentCredits.Checks.OwnWallet
    end

    # Checking reads the chain and credits only what it proves, so anyone may ask.
    policy action([:check, :check_due]) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end
  end
end

defmodule RegentCredits.DepositCursor do
  @moduledoc """
  How far the Credits deposits on a chain have been read: the next block to
  read. Base has the one row, opened by the library's migrations at the first
  block of 6 October 2026, before any Credits purchase existed.

  The site's Oban reads on from it every minute (`RegentCredits.Deposits`),
  so every Credits deposit is credited whether or not a page reported it.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "deposit_cursors"
  end

  oban do
    triggers do
      trigger :read do
        action :read_due
        scheduler_cron "* * * * *"
        queue :regent_credits
        max_attempts 3
        worker_module_name RegentCredits.DepositCursor.AshOban.Worker.Read
        scheduler_module_name RegentCredits.DepositCursor.AshOban.Scheduler.Read
      end
    end
  end

  attributes do
    attribute :chain, :atom do
      primary_key? true
      allow_nil? false
      public? true
      constraints one_of: [:base]
    end

    attribute :next_block, :integer do
      allow_nil? false
      public? true
      constraints min: 0
    end

    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    # Moves on only from the block this reader started at, so two sites
    # reading the same chain at once never step it back.
    update :advance do
      argument :from, :integer, allow_nil?: false
      argument :to, :integer, allow_nil?: false
      change filter(expr(next_block == ^arg(:from)))
      change set_attribute(:next_block, arg(:to))
    end

    action :read_due do
      description "The Oban read of a chain's new Credits deposits."
      argument :primary_key, :map, allow_nil?: false

      run fn input, _context ->
        input.arguments.primary_key["chain"]
        |> String.to_existing_atom()
        |> RegentCredits.Deposits.read()
      end
    end
  end

  policies do
    # The site's Oban reads the chain and credits only what it proves.
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
    end
  end
end

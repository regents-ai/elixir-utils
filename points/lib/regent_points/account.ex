defmodule RegentPoints.Account do
  @moduledoc false
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "accounts"
    schema("regent_points")
    repo(&RegentPoints.repo/2)

    check_constraints do
      check_constraint(:nft_count, "holdings_nonnegative",
        check: "nft_count IS NULL OR nft_count >= 0"
      )
    end
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false
    attribute :nft_count, :integer, constraints: [min: 0]
    attribute :nft_block, :integer
    attribute :nft_block_hash, :string
    attribute :nft_checked_at, :utc_datetime_usec
    attribute :wallet_digest, :string, sensitive?: true
    create_timestamp :inserted_at
  end

  actions do
    read :read do
      primary? true
    end

    create :open do
      accept [:id]
      upsert? true
      upsert_identity :canonical_account
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
    end

    update :record_holdings do
      accept [:nft_count, :nft_block, :nft_block_hash, :nft_checked_at, :wallet_digest]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(id == ^actor(:human_account_id))
    end
  end

  identities do
    identity :canonical_account, [:id]
  end

  relationships do
    belongs_to :human_account, RegentPoints.HumanAccount do
      source_attribute :id
      define_attribute? false
      attribute_type :integer
      allow_nil? false
    end

    has_many :entries, RegentPoints.Entry, destination_attribute: :account_id
  end

  aggregates do
    sum :balance_micro, :entries, :points_micro_delta, default: 0
  end

  calculations do
    calculate :bonus_percent, :integer, RegentPoints.Bonus.Calculation
  end

  pub_sub do
    module RegentPoints.PubSub
    name :regent_points
    prefix "points"
    broadcast_type :broadcast
    transform fn _notification -> :points_changed end
    publish :record_holdings, [:id]
  end
end

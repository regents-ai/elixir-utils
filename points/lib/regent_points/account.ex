defmodule RegentPoints.Account do
  @moduledoc false
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "accounts"
    schema("regent_points")
    repo(&RegentPoints.repo/2)
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false
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
    has_many :period_bonuses, RegentPoints.PeriodBonus, destination_attribute: :account_id
  end

  aggregates do
    sum :earned_micro, :entries, :points_micro_delta, default: 0
    sum :bonus_micro, :period_bonuses, :bonus_micro, default: 0
  end

  calculations do
    calculate :balance_micro, :integer, expr(earned_micro + bonus_micro)
  end
end

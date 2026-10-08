defmodule RegentPoints.Entry do
  @moduledoc false
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "point_entries"
    schema("regent_points")
    repo(&RegentPoints.repo/2)

    check_constraints do
      check_constraint(:points_micro_delta, "entry_amount_parts",
        check: "points_micro_delta = base_points_micro + bonus_points_micro"
      )

      check_constraint(:base_points_micro, "entry_direction",
        check:
          "(reversal_of_entry_id IS NULL AND base_points_micro >= 0 AND bonus_points_micro >= 0) OR (reversal_of_entry_id IS NOT NULL AND base_points_micro < 0 AND bonus_points_micro <= 0)"
      )

      check_constraint(:bonus_percent, "entry_bonus_tier",
        check: "bonus_percent IN (#{Enum.join(RegentPoints.Bonus.allowed_percentages(), ",")})"
      )

      check_constraint(:cap_reduction_micro, "entry_cap_nonnegative",
        check: "cap_reduction_micro >= 0"
      )
    end

    custom_indexes do
      index([:account_id, :recorded_at])
      index([:reversal_of_entry_id])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :program_id, :string, allow_nil?: false
    attribute :account_id, :integer, allow_nil?: false
    attribute :event_id, :uuid, allow_nil?: false
    attribute :award_key, :string, allow_nil?: false
    attribute :rule_id, :string, allow_nil?: false
    attribute :rule_version, :integer, allow_nil?: false
    attribute :source_app, :string, allow_nil?: false
    attribute :actor_kind, :string, allow_nil?: false
    attribute :actor_id, :string, allow_nil?: false
    attribute :category, :string, allow_nil?: false
    attribute :milestone_key, :string
    attribute :base_points_micro, :integer, allow_nil?: false
    attribute :bonus_points_micro, :integer, allow_nil?: false
    attribute :cap_reduction_micro, :integer, allow_nil?: false, default: 0
    attribute :bonus_percent, :integer, allow_nil?: false
    attribute :points_micro_delta, :integer, allow_nil?: false
    attribute :purchased_usdc_atomic, :integer
    attribute :earned_at, :utc_datetime_usec, allow_nil?: false
    create_timestamp :recorded_at
    attribute :reversal_of_entry_id, :uuid
    attribute :reason_code, :string, allow_nil?: false
  end

  relationships do
    belongs_to :account, RegentPoints.Account,
      define_attribute?: false,
      source_attribute: :account_id,
      attribute_type: :integer

    belongs_to :event, RegentPoints.Event,
      define_attribute?: false,
      source_attribute: :event_id

    belongs_to :reversal_of_entry, __MODULE__,
      define_attribute?: false,
      source_attribute: :reversal_of_entry_id
  end

  actions do
    read :read do
      primary? true
    end

    read :history do
      prepare build(sort: [recorded_at: :desc, id: :desc])

      pagination do
        keyset? true
        required? true
        default_limit 50
        max_page_size 100
      end
    end

    create :append do
      accept [
        :program_id,
        :account_id,
        :event_id,
        :award_key,
        :rule_id,
        :rule_version,
        :source_app,
        :actor_kind,
        :actor_id,
        :category,
        :milestone_key,
        :base_points_micro,
        :bonus_points_micro,
        :cap_reduction_micro,
        :bonus_percent,
        :points_micro_delta,
        :purchased_usdc_atomic,
        :earned_at,
        :reversal_of_entry_id,
        :reason_code
      ]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(account_id == ^actor(:human_account_id))
    end
  end

  identities do
    identity :logical_award, [:program_id, :award_key]
  end

  pub_sub do
    module RegentPoints.PubSub
    name :regent_points
    prefix "points"
    broadcast_type :broadcast
    transform fn _notification -> :points_changed end
    publish :append, [:account_id]
  end
end

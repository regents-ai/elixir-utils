defmodule RegentPoints.TransferCursor do
  @moduledoc false
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "nft_transfer_cursors"
    schema("regent_points")
    repo(&RegentPoints.repo/2)
  end

  attributes do
    uuid_primary_key :id
    attribute :chain_id, :integer, allow_nil?: false
    attribute :next_block, :integer, allow_nil?: false
    attribute :previous_hash, :string
    attribute :stopped_at, :integer
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    read :read do
      primary? true
    end

    create :start do
      accept [:chain_id, :next_block]
      upsert? true
      upsert_identity :chain
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
    end

    update :advance do
      accept [:next_block, :previous_hash]
    end

    update :stop do
      accept [:stopped_at]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      forbid_if always()
    end
  end

  identities do
    identity :chain, [:chain_id]
  end
end

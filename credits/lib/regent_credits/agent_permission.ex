defmodule RegentCredits.AgentPermission do
  @moduledoc """
  What one person lets one of their linked agents spend, set at
  regents.sh/account: on or off, the most per spend, a daily limit and the
  sites it may spend on. An agent with no row cannot spend.

  The daily limit counts every hold the agent made in the last 24 hours that
  is still held or was spent; a hold that comes back gives its room back.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "agent_permissions"
  end

  attributes do
    uuid_primary_key :id
    attribute :privy_user_id, :string, allow_nil?: false, public?: true
    attribute :agent_address, :string, allow_nil?: false, public?: true
    attribute :enabled, :boolean, allow_nil?: false, default: false, public?: true
    attribute :max_per_spend, :decimal, allow_nil?: false, public?: true
    attribute :daily_limit, :decimal, allow_nil?: false, public?: true
    attribute :sites, {:array, :string}, allow_nil?: false, default: [], public?: true
    update_timestamp :updated_at
  end

  identities do
    identity :agent, [:privy_user_id, :agent_address]
  end

  actions do
    defaults [:read]

    create :set do
      description "Saves the person's settings for one agent."
      accept [:privy_user_id, :agent_address, :enabled, :max_per_spend, :daily_limit, :sites]
      upsert? true
      upsert_identity :agent
      upsert_fields [:enabled, :max_per_spend, :daily_limit, :sites, :updated_at]

      change fn changeset, _context ->
        Ash.Changeset.update_change(changeset, :agent_address, &String.downcase/1)
      end
    end
  end

  validations do
    validate compare(:max_per_spend, greater_than_or_equal_to: 0)
    validate compare(:daily_limit, greater_than_or_equal_to: 0)
  end

  policies do
    # Only regents.sh/account changes these, for the signed-in person.
    policy action(:set) do
      forbid_unless actor_attribute_equals(:site, "regents")
      authorize_if RegentCredits.Checks.OwnCredits
    end

    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end
  end
end

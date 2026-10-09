defmodule RegentCredits.AgentPermission do
  @moduledoc """
  What one person lets one of their linked agents spend, set at
  regents.sh/account: on or off, the most per spend, a daily limit and the
  sites it may spend on. An agent with no row cannot spend.

  Each agent's daily limit counts all of the owner's agent holds across sites
  in the last 24 hours that are still held or were spent; a returned hold gives
  its room back. Switching agents, sites or pairing episodes does not reset usage.
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
    attribute :pairing_id, :uuid, public?: true
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
      upsert_fields [:pairing_id, :enabled, :max_per_spend, :daily_limit, :sites, :updated_at]

      change fn changeset, _context ->
        Ash.Changeset.update_change(changeset, :agent_address, &String.downcase/1)
      end

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          if Ash.Changeset.get_attribute(changeset, :enabled) == true and
               not RegentCredits.agent_grants_enabled?() do
            Ash.Changeset.add_error(changeset,
              field: :enabled,
              message:
                "Agent spending grants are unavailable until the shared rollout is complete."
            )
          else
            changeset
          end
        end)
      end

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          owner = Ash.Changeset.get_attribute(changeset, :privy_user_id)
          wallet = Ash.Changeset.get_attribute(changeset, :agent_address)

          case RegentAgents.Authority.lock_current(
                 RegentCredits.repo(nil, :mutate),
                 owner,
                 wallet
               ) do
            {:ok, pairing} ->
              Ash.Changeset.force_change_attribute(changeset, :pairing_id, pairing.id)

            {:error, _} ->
              Ash.Changeset.add_error(changeset,
                field: :agent_address,
                message: "must have an active pairing with this account"
              )
          end
        end)
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

defmodule RegentPoints.HumanAccount do
  @moduledoc "Read-only foreign-key target in Regent's canonical account schema. The host owns account lookup and verification."
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentPoints.repo/2
    table "platform_human_users"
    schema "regent_names"
    migrate? false
  end

  attributes do
    integer_primary_key :id
    attribute :privy_user_id, :string, allow_nil?: false, sensitive?: true
  end

  relationships do
    # The shared record of an account an agent opened for itself (elixir-utils agents).
    has_one :opening, RegentAgents.OpenedAccount do
      source_attribute :privy_user_id
      destination_attribute :privy_user_id
    end
  end

  aggregates do
    # Read whatever the shared record's own rules say: an opening hidden from this
    # read would count the account as a person's and pay it.
    exists :agent_opened, :opening do
      authorize? false
    end
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end
end

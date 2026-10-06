defmodule RegentCredits.FirstUse do
  @moduledoc """
  When a Privy account first used Credits: its first hold of any kind, even
  one that was given back. From then on its purchased Credits cannot be
  refunded.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "first_uses"
  end

  attributes do
    attribute :privy_user_id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :hold_key, :string, allow_nil?: false, public?: true
    create_timestamp :used_at, public?: true
  end

  actions do
    defaults [:read]

    # Keeps the first use: a later hold upserts nothing.
    create :record do
      accept [:privy_user_id, :hold_key]
      upsert? true
      upsert_fields []
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end
  end
end

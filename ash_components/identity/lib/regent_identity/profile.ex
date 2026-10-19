defmodule RegentIdentity.Profile do
  @moduledoc """
  One shared profile per Privy account: display name, selected wallet, the
  verified linked wallets and X account, and when that proof was issued.
  """
  use Ash.Resource,
    domain: RegentIdentity,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentIdentity.repo/2
    schema "regent_identity"
    table "profiles"
    migrate? false
  end

  attributes do
    uuid_primary_key :id
    attribute :app_id, :string, allow_nil?: false, sensitive?: true
    attribute :privy_user_id, :string, allow_nil?: false, sensitive?: true
    # A name shows on every Regent site, so it holds no hidden characters (founder,
    # 2026-10-19): no control, line or paragraph separator, or format character,
    # which covers the marks that turn the text around them the other way. Two
    # format characters are kept where they draw something: a zero-width joiner or
    # non-joiner between two visible characters (emoji joins, Persian script), and
    # tag characters inside a complete flag, from U+1F3F4 to U+E007F.
    attribute :display_name, :string,
      constraints: [
        max_length: 80,
        match:
          ~r/\A(?:\x{1F3F4}[\x{E0020}-\x{E007E}]+\x{E007F}|(?<=[^\p{Cc}\p{Cf}\p{Z}])[\x{200C}\x{200D}](?=[^\p{Cc}\p{Cf}\p{Z}])|[^\p{Cc}\p{Cf}\p{Zl}\p{Zp}])*\z/u
      ]

    attribute :wallet_address, :string, sensitive?: true

    attribute :wallet_addresses, {:array, :string},
      allow_nil?: false,
      default: [],
      sensitive?: true

    attribute :x_subject, :string, sensitive?: true
    attribute :x_username, :string
    attribute :x_display_name, :string
    attribute :proof_issued_at, :integer, allow_nil?: false, sensitive?: true
    timestamps()
  end

  identities do
    identity :privy_subject, [:app_id, :privy_user_id]
    identity :x_subject_owner, [:app_id, :x_subject]
  end

  actions do
    read :mine do
      get? true
      filter expr(app_id == ^actor(:app_id) and privy_user_id == ^actor(:privy_user_id))
    end

    # Only `RegentIdentity.ProfileName` reads this, unauthorized: names are
    # public, and it selects nothing but the name.
    read :names do
      argument :app_id, :string, allow_nil?: false
      argument :privy_user_ids, {:array, :string}, allow_nil?: false
      filter expr(app_id == ^arg(:app_id) and privy_user_id in ^arg(:privy_user_ids))
    end

    create :register do
      accept []
      change RegentIdentity.ProofAttributes
    end

    update :refresh do
      accept []
      require_atomic? false
      change RegentIdentity.ProofAttributes
    end

    update :edit do
      accept [:display_name, :wallet_address]
      require_atomic? false
      change RegentIdentity.SelectedWallet
    end
  end

  policies do
    policy always() do
      authorize_if RegentIdentity.VerifiedActor
    end

    policy action([:mine, :refresh, :edit]) do
      authorize_if expr(app_id == ^actor(:app_id) and privy_user_id == ^actor(:privy_user_id))
    end
  end
end

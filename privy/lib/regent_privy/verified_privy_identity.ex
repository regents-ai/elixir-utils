defmodule RegentPrivy.VerifiedPrivyIdentity do
  @moduledoc """
  Identity data extracted from a verified Privy identity token.
  """

  @type linked_social :: %{
          provider: :x | :github | :farcaster,
          subject: String.t(),
          username: String.t() | nil,
          display_name: String.t() | nil
        }

  @type t :: %__MODULE__{
          claims: map(),
          privy_user_id: String.t(),
          wallet_address: String.t() | nil,
          wallet_addresses: [String.t()],
          linked_socials: [linked_social()]
        }

  defstruct claims: %{},
            privy_user_id: nil,
            wallet_address: nil,
            wallet_addresses: [],
            linked_socials: []
end

defmodule RegentCredits.Actor do
  @moduledoc """
  Who is asking the library to do something. The site builds it from what it
  has already verified: its own sign-in for a person, its agent sign-in for an
  agent, its own server code for the site itself, and its admin rule for an
  admin. The library decides what each one may do; it never checks sign-ins.

    * `person/3`: a signed-in person, spending or reading their own Credits,
      with the wallets the site's sign-in verified for them. A person reports
      purchases only from those wallets.
    * `agent/3`: an agent linked to that person, spending within the limits
      the person set at regents.sh/account.
    * `site/1`: the site's own server code: giving back, charging and settling
      what it held, recording payments and attaching held gifts.
    * `admin/1`: a person the library's `:admins` setting names.
  """

  @enforce_keys [:role, :site]
  defstruct [:role, :site, :privy_user_id, :agent_address, wallets: []]

  @type t :: %__MODULE__{
          role: :person | :agent | :site | :admin,
          site: String.t(),
          privy_user_id: String.t() | nil,
          agent_address: String.t() | nil,
          wallets: [String.t()]
        }

  @spec person(String.t(), [String.t()], String.t()) :: t()
  def person(privy_user_id, wallets, site) do
    %__MODULE__{
      role: :person,
      site: site,
      privy_user_id: privy_user_id,
      wallets: Enum.map(wallets, &RegentChain.Address.normalize!/1)
    }
  end

  @spec agent(String.t(), String.t(), String.t()) :: t()
  def agent(privy_user_id, agent_address, site) do
    %__MODULE__{
      role: :agent,
      site: site,
      privy_user_id: privy_user_id,
      agent_address: String.downcase(agent_address)
    }
  end

  @spec site(String.t()) :: t()
  def site(site), do: %__MODULE__{role: :site, site: site}

  @spec admin(String.t()) :: t()
  def admin(privy_user_id),
    do: %__MODULE__{role: :admin, site: "regents", privy_user_id: privy_user_id}
end

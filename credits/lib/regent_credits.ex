defmodule RegentCredits do
  @moduledoc """
  Regent Credits: one prepaid balance per Privy account, shared by every
  Regent site. One Credit is one US dollar.

  Credits arrive by purchase (`RegentCredits.Purchase`, USDC on Base or
  Ethereum) or as a gift from an admin (`RegentCredits.Gift`), and leave
  through holds a site places when someone spends (`RegentCredits.Hold`) or
  a refund (`RegentCredits.Refund`). Every movement is a transfer in a double-entry
  ledger kept in the `regent_credits` schema of the site's own database, so
  a site's change and its Credits commit or fail together.

  A site supplies its repository, PubSub and admins, declares the Credits
  currency, and passes an `RegentCredits.Actor` with every call:

      config :ex_money, custom_currencies: [{:XRC, name: "Credits", digits: 6}]

      config :regent_credits,
        repo: MySite.Repo,
        pubsub: MySite.PubSub,
        admins: ["did:privy:..."],
        chain_client: MySite.Chain.Client,
        chains: %{base: %{...}, ethereum: %{...}}

  Purchases are checked by the site's Oban (see `RegentCredits.Purchase`)
  and the chain settings are described in `RegentCredits.Chains`.

  Every change to a person's balance, made on any site, reaches pages showing
  it: a site starts `RegentCredits.Listener` and its pages subscribe to
  `topic/1`.

  The schema is migrated with `RegentCredits.Migrator`: locally by each site,
  and in production only by Regents.
  """

  use Ash.Domain, otp_app: :regent_credits

  alias RegentCredits.Ledger

  resources do
    resource RegentCredits.Ledger.Account
    resource RegentCredits.Ledger.Transfer
    resource RegentCredits.Ledger.Balance
    resource RegentCredits.FirstUse
    resource RegentCredits.Wallet
    resource RegentCredits.DepositCursor

    resource RegentCredits.History do
      define :history, action: :history
    end

    resource RegentCredits.Purchase do
      define :report_purchase,
        action: :report,
        args: [:privy_user_id, :wallet, :chain, :amount, :number, :tx_hash]

      define :check_purchase, action: :check, args: [:id]
      define :purchases, action: :read
    end

    resource RegentCredits.Gift do
      define :give, args: [:key, :to, :amount]
      define :attach_wallets, args: [:privy_user_id, :wallets]
      define :gifts, action: :read
    end

    resource RegentCredits.Refund do
      define :start_refund, action: :start, args: [:purchase_id]
      define :close_refund, action: :close, args: [:id, :tx_hash]
      define :refunds, action: :read
    end

    resource RegentCredits.AgentPermission do
      define :set_agent_permission, action: :set
      define :agent_permissions, action: :read
    end

    resource RegentCredits.Hold do
      define :hold, args: [:key, :privy_user_id, :amount, :purpose]
      define :give_back, args: [:key, :reason]
      define :charge, args: [:key]
      define :carry_over, args: [:key, :to_key, :purpose]
      define :settle, args: [:key, :returned, :used, :forfeited]
      define :pay_bounty, args: [:key, :to]
      define :take_back, args: [:key]
      define :lock_holds, args: [:keys, :privy_user_ids]
      define :holds, action: :read
    end
  end

  @doc false
  def repo(_resource, _operation), do: Application.fetch_env!(:regent_credits, :repo)

  @doc """
  Whether owners may enable agent spending grants. Defaults to false until every
  shared Credits writer has adopted pairing-bound grants.
  """
  @spec agent_grants_enabled?() :: boolean()
  def agent_grants_enabled? do
    Application.get_env(:regent_credits, :agent_grants_enabled, false) == true
  end

  @doc """
  The PubSub topic that hears `:credits_changed` when a person's balance
  changes on any Regent site: a purchase, a gift, a hold or its close.
  """
  @spec topic(String.t()) :: String.t()
  def topic(privy_user_id), do: "regent_credits:" <> privy_user_id

  @doc false
  def channel, do: "regent_credits"

  @doc false
  # Tells every site through the shared database. Inside a transaction the
  # notice goes out when it commits, once however often it was sent, and not
  # at all if it rolls back.
  def announce(privy_user_id) do
    Ecto.Adapters.SQL.query!(repo(nil, :mutate), "SELECT pg_notify($1, $2)", [
      channel(),
      privy_user_id
    ])

    :ok
  end

  @doc """
  A person's Credits: what they can spend, split into given and purchased,
  and what is set aside in holds. Read without locking, for display.
  """
  @spec balance(String.t()) :: %{
          available: Decimal.t(),
          given: Decimal.t(),
          purchased: Decimal.t(),
          held: Decimal.t()
        }
  def balance(privy_user_id) do
    [given, purchased, held_given, held_purchased] =
      privy_user_id |> Ledger.person() |> Ledger.balances()

    %{
      available: Decimal.add(given, purchased),
      given: given,
      purchased: purchased,
      held: Decimal.add(held_given, held_purchased)
    }
  end
end

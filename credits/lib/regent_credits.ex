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

  A site supplies its repository and admins, declares the Credits currency,
  and passes an `RegentCredits.Actor` with every call:

      config :ex_money, custom_currencies: [{:XRC, name: "Credits", digits: 6}]

      config :regent_credits,
        repo: MySite.Repo,
        admins: ["did:privy:..."],
        chain_client: MySite.Chain.Client,
        chains: %{base: %{...}, ethereum: %{...}}

  Purchases are checked by the site's Oban (see `RegentCredits.Purchase`)
  and the chain settings are described in `RegentCredits.Chains`.

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
      define :holds, action: :read
    end
  end

  @doc false
  def repo(_resource, _operation), do: Application.fetch_env!(:regent_credits, :repo)

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

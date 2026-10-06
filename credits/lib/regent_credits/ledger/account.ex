defmodule RegentCredits.Ledger.Account do
  @moduledoc """
  One ledger account. Every Privy account has four: `given` and `purchased`
  Credits it can spend, and `held_given` and `held_purchased` set aside by a
  hold. `address_given` keeps given Credits for a wallet address that has no
  account yet. The `regent_*` accounts are where purchased and given Credits
  come from and where revenue and refunds go.

  Only the library's own operations open, lock and move accounts.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDoubleEntry.Account]

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "accounts"
  end

  account do
    transfer_resource RegentCredits.Ledger.Transfer
    balance_resource RegentCredits.Ledger.Balance
  end

  aggregates do
    # The newest balance row, whatever its timestamp: sites on other machines
    # write transfers too, so a cut-off at this machine's clock could miss one.
    first :current_balance, :balances, :balance do
      sort transfer_id: :desc
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
    end
  end
end

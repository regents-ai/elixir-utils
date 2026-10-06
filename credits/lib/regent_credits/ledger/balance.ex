defmodule RegentCredits.Ledger.Balance do
  @moduledoc "An account's balance as of each transfer, kept by the ledger itself."
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDoubleEntry.Balance]

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "balances"

    references do
      reference :transfer, on_delete: :delete
    end
  end

  balance do
    transfer_resource RegentCredits.Ledger.Transfer
    account_resource RegentCredits.Ledger.Account
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, required?: false
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
    end
  end
end

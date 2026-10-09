defmodule RegentCredits.Ledger.Transfer do
  @moduledoc """
  One movement of Credits between two ledger accounts. `operation` names the
  library operation that made it, such as `hold:<key>`, so a person's history
  reads as what happened. Transfers are never changed or removed.
  """
  use Ash.Resource,
    otp_app: :regent_credits,
    domain: RegentCredits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDoubleEntry.Transfer]

  postgres do
    repo &RegentCredits.repo/2
    schema "regent_credits"
    table "transfers"

    custom_indexes do
      index [:from_account_id, :id], concurrently: true
      index [:to_account_id, :id], concurrently: true
    end

    custom_statements do
      statement :refuse_change do
        up """
        CREATE FUNCTION regent_credits.refuse_change() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          RAISE EXCEPTION 'regent_credits.% rows are final', TG_TABLE_NAME;
        END;
        $$
        """

        down "DROP FUNCTION regent_credits.refuse_change()"
      end

      statement :transfers_are_final do
        up """
        CREATE TRIGGER transfers_are_final BEFORE UPDATE OR DELETE ON regent_credits.transfers
          FOR EACH ROW EXECUTE FUNCTION regent_credits.refuse_change()
        """

        down "DROP TRIGGER transfers_are_final ON regent_credits.transfers"
      end
    end
  end

  transfer do
    account_resource RegentCredits.Ledger.Account
    balance_resource RegentCredits.Ledger.Balance
    create_accept [:operation]
  end

  attributes do
    attribute :operation, :string, allow_nil?: false, public?: true
  end

  policies do
    policy action_type(:read) do
      authorize_if RegentCredits.Checks.Admin
    end
  end
end

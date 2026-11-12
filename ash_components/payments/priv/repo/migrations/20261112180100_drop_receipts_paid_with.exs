defmodule RegentPayments.Migrations.DropReceiptsPaidWith do
  @moduledoc """
  Never apply this without the founder's own named go. Every site that takes
  payments applies this library's migrations to the one shared database when it
  moves to a new version.

  Drops a receipt's `paid_with` column and the `paid_with_names_how` rule that
  read it. Apply it only once every site runs a version without the field
  (`20261112180000_receipts_paid_with_default` and later): a site still on an
  older version reads and writes the column, and its receipts fail once the
  column is gone. The receipts paid in Credits before 6 November 2026 stay; they
  are the ones that name no paying wallet.
  """

  use Ecto.Migration

  def up do
    drop(constraint(:payment_receipts, :paid_with_names_how, prefix: "regent_payments"))

    alter table(:payment_receipts, prefix: "regent_payments") do
      remove(:paid_with)
    end
  end

  def down do
    raise "Payment records are retained evidence of money that moved; restore a reviewed recovery copy instead."
  end
end

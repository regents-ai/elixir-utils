defmodule RegentPayments.Migrations.ReceiptsPaidInUsdc do
  @moduledoc """
  Every payment is now paid in USDC from the payer's wallet, so a new receipt
  no longer names how it was paid: `paid_with` takes "usdc" as its default
  again. The receipts already written, in USDC and in Regent Credits, stay as
  they are, with their column and its check.
  """

  use Ecto.Migration

  def up do
    alter table(:payment_receipts, prefix: "regent_payments") do
      modify(:paid_with, :text, default: "usdc")
    end
  end

  def down do
    alter table(:payment_receipts, prefix: "regent_payments") do
      modify(:paid_with, :text, default: nil)
    end
  end
end

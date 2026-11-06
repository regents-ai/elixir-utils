defmodule RegentPoints.Repo.Migrations.PaymentOnce do
  @moduledoc """
  One payment pays dollar points once: its row on account 0 counts at most one
  award (RegentPoints.Award). A correction may be 0, to free the payment of a
  0-point spending award (RegentPoints.Reverse).
  """

  use Ecto.Migration

  def up do
    create constraint(:point_cap_usage, :payment_once,
             check: """
               cap_scope NOT LIKE 'payment:%' OR award_count <= 1
             """,
             prefix: "regent_points"
           )

    drop_if_exists(constraint(:point_entries, :entry_direction, prefix: "regent_points"))

    create constraint(:point_entries, :entry_direction,
             check: """
               (reversal_of_entry_id IS NULL AND points_micro_delta >= 0) OR (reversal_of_entry_id IS NOT NULL AND points_micro_delta <= 0)
             """,
             prefix: "regent_points"
           )
  end

  def down do
    drop_if_exists(constraint(:point_entries, :entry_direction, prefix: "regent_points"))

    create constraint(:point_entries, :entry_direction,
             check: """
               (reversal_of_entry_id IS NULL AND points_micro_delta >= 0) OR (reversal_of_entry_id IS NOT NULL AND points_micro_delta < 0)
             """,
             prefix: "regent_points"
           )

    drop_if_exists(constraint(:point_cap_usage, :payment_once, prefix: "regent_points"))
  end
end

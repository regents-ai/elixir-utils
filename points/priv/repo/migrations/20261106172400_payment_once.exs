defmodule RegentPoints.Repo.Migrations.PaymentOnce do
  @moduledoc """
  One payment pays dollar points once: one row per payment on account 0, counting
  at most one award (RegentPoints.Award). A correction may be 0, only of a
  spending award and at most once, to free a 0-point spending award's payment
  (RegentPoints.Reverse).

  It applies in one transaction and waits at most 5 seconds for a lock. Rolling
  back is refused once any 0 correction exists, and then changes nothing: the old
  direction check allows none.
  """

  use Ecto.Migration

  @prefix "regent_points"

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    create constraint(:point_cap_usage, :payment_once,
             check: "cap_scope NOT LIKE 'payment:%' OR award_count <= 1",
             prefix: @prefix
           )

    create unique_index(:point_cap_usage, [:cap_scope],
             name: "point_cap_usage_payment_row_once_index",
             where: "cap_scope LIKE 'payment:%'",
             prefix: @prefix
           )

    drop(constraint(:point_entries, :entry_direction, prefix: @prefix))

    create constraint(:point_entries, :entry_direction,
             check: """
             (reversal_of_entry_id IS NULL AND points_micro_delta >= 0) OR
             (reversal_of_entry_id IS NOT NULL AND
               (points_micro_delta < 0 OR (points_micro_delta = 0 AND category = 'spending')))
             """,
             prefix: @prefix
           )

    create unique_index(:point_entries, [:reversal_of_entry_id],
             name: "point_entries_one_zero_correction_index",
             where: "points_micro_delta = 0",
             prefix: @prefix
           )
  end

  def down do
    execute("SET LOCAL lock_timeout = '5s'")

    drop(
      index(:point_entries, [:reversal_of_entry_id],
        name: "point_entries_one_zero_correction_index",
        prefix: @prefix
      )
    )

    drop(constraint(:point_entries, :entry_direction, prefix: @prefix))

    create constraint(:point_entries, :entry_direction,
             check: """
             (reversal_of_entry_id IS NULL AND points_micro_delta >= 0) OR
             (reversal_of_entry_id IS NOT NULL AND points_micro_delta < 0)
             """,
             prefix: @prefix
           )

    drop(
      index(:point_cap_usage, [:cap_scope],
        name: "point_cap_usage_payment_row_once_index",
        prefix: @prefix
      )
    )

    drop(constraint(:point_cap_usage, :payment_once, prefix: @prefix))
  end
end

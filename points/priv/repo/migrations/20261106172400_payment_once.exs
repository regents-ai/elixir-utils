defmodule RegentPoints.Repo.Migrations.PaymentOnce do
  @moduledoc """
  One payment pays dollar points once: one row per payment on account 0, counting
  at most one award (RegentPoints.Award). A correction may be 0, only of a
  spending award and at most once, to free a 0-point spending award's payment
  (RegentPoints.Reverse).

  Each step is its own transaction and waits at most 5 seconds for a lock. A check
  is added unvalidated, which holds its table only for a moment, then validated,
  which reads every row without stopping writes. So the steps are not wrapped in
  one transaction, and the migration lock is off: only Regents runs production
  migrations, from one place. Each step can run again.

  Rolling back is refused once any 0 correction exists, and then changes nothing:
  the old direction check allows none.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @caps "regent_points.point_cap_usage"
  @entries "regent_points.point_entries"

  def up do
    step("""
    ALTER TABLE #{@caps} DROP CONSTRAINT IF EXISTS payment_once,
      ADD CONSTRAINT payment_once
      CHECK (cap_scope NOT LIKE 'payment:%' OR award_count <= 1) NOT VALID
    """)

    step("ALTER TABLE #{@caps} VALIDATE CONSTRAINT payment_once")

    step("""
    CREATE UNIQUE INDEX IF NOT EXISTS point_cap_usage_payment_row_once_index
      ON #{@caps} (cap_scope) WHERE cap_scope LIKE 'payment:%'
    """)

    step("""
    ALTER TABLE #{@entries} DROP CONSTRAINT IF EXISTS entry_direction,
      ADD CONSTRAINT entry_direction
      CHECK ((reversal_of_entry_id IS NULL AND points_micro_delta >= 0) OR
        (reversal_of_entry_id IS NOT NULL AND
          (points_micro_delta < 0 OR (points_micro_delta = 0 AND category = 'spending'))))
      NOT VALID
    """)

    step("ALTER TABLE #{@entries} VALIDATE CONSTRAINT entry_direction")

    step("""
    CREATE UNIQUE INDEX IF NOT EXISTS point_entries_one_zero_correction_index
      ON #{@entries} (reversal_of_entry_id) WHERE points_micro_delta = 0
    """)
  end

  def down do
    step("""
    ALTER TABLE #{@entries} DROP CONSTRAINT IF EXISTS entry_direction,
      ADD CONSTRAINT entry_direction
      CHECK ((reversal_of_entry_id IS NULL AND points_micro_delta >= 0) OR
        (reversal_of_entry_id IS NOT NULL AND points_micro_delta < 0))
    """)

    step("DROP INDEX IF EXISTS regent_points.point_entries_one_zero_correction_index")
    step("DROP INDEX IF EXISTS regent_points.point_cap_usage_payment_row_once_index")
    step("ALTER TABLE #{@caps} DROP CONSTRAINT IF EXISTS payment_once")
  end

  defp step(sql) do
    {:ok, _} =
      repo().transaction(fn ->
        repo().query!("SET LOCAL lock_timeout = '5s'")
        repo().query!(sql)
      end)
  end
end

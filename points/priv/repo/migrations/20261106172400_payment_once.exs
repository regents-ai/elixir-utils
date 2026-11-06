defmodule RegentPoints.Repo.Migrations.PaymentOnce do
  @moduledoc """
  One payment pays dollar points once: its row on account 0 counts at most one
  award (RegentPoints.Award).
  """

  use Ecto.Migration

  def up do
    create constraint(:point_cap_usage, :payment_once,
             check: """
               cap_scope NOT LIKE 'payment:%' OR award_count <= 1
             """,
             prefix: "regent_points"
           )
  end

  def down do
    drop_if_exists(constraint(:point_cap_usage, :payment_once, prefix: "regent_points"))
  end
end

defmodule RegentCredits.Credited do
  @moduledoc """
  The site's notice that a purchase was credited. `credited/1` runs inside the
  credit's own transaction, after the purchase is marked credited, so any work the
  site queues there commits or rolls back with the credit. It returns `:ok` and
  never fails the credit.
  """

  @callback credited(purchase :: struct()) :: :ok
end

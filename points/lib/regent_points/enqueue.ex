defmodule RegentPoints.Enqueue do
  @moduledoc """
  Best-effort Points scheduling inside the host's source transaction. The one Oban
  insert commits or rolls back with the source. PostgreSQL's statement savepoint
  isolates an insert failure so Points cannot abort the surrounding action.

  Failed enqueue emits telemetry and returns :not_queued; the authoritative source
  remains available for an operator to resubmit. Never repeat the person's action.
  Use the site's Oban with the same Repo as its source transaction.
  """
  def call(worker, args) do
    # insert_all passes standard Repo options through; insert/2 drops :mode.
    # Oban's basic engine skips a worker's unique option on insert_all. Both jobs
    # queued here are safe to repeat: the ledger deduplicates verified source
    # facts, and a holdings refresh keeps the newest block under the account lock.
    opts = if RegentPoints.repo(nil, :mutate).in_transaction?(), do: [mode: :savepoint], else: []

    case Oban.insert_all([worker.new(args)], opts) do
      [job] -> {:ok, %{status: :queued, id: job.id}}
      _ -> failed(worker)
    end
  rescue
    _ -> failed(worker)
  end

  defp failed(worker) do
    :telemetry.execute([:regent_points, :enqueue, :failure], %{count: 1}, %{worker: worker})
    {:ok, %{status: :not_queued, reason: :points_unavailable}}
  end
end

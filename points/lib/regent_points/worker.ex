defmodule RegentPoints.Worker do
  @moduledoc """
  Awards one recorded event. A Base outage retries for about six hours; on the last
  attempt the event is finished as not counted with reason `chain_unavailable`.
  """
  use Oban.Worker,
    queue: :points,
    max_attempts: 12,
    unique: [keys: [:event_id], period: :infinity, states: :incomplete]

  @impl true
  def backoff(%Oban.Job{attempt: attempt}), do: min(60 * 2 ** (attempt - 1), 3600)

  @impl true
  def perform(%Oban.Job{args: %{"event_id" => id}, attempt: attempt, max_attempts: max}) do
    case RegentPoints.process_event(id, attempt == max, actor: RegentPoints.Store.system()) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

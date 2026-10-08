defmodule RegentPoints.Worker do
  @moduledoc false
  use Oban.Worker,
    queue: :points,
    max_attempts: 10,
    unique: [keys: [:event_id], period: :infinity, states: :incomplete]

  @impl true
  def perform(%Oban.Job{args: %{"event_id" => id}}) do
    case RegentPoints.process_event(id, actor: RegentPoints.Store.system()) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

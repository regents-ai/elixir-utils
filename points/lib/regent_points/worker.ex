defmodule RegentPoints.Worker do
  @moduledoc """
  Awards one recorded event under its account's lock. Oban owns retries. When the
  last attempt fails, the event is rejected as `award_failed`, so the account's
  summary never counts it as pending forever.
  """
  use Oban.Worker,
    queue: :points,
    max_attempts: 10,
    unique: [keys: [:event_id], period: :infinity, states: :incomplete]

  alias RegentPoints.Store

  @impl true
  def perform(%Oban.Job{args: %{"event_id" => id}} = job) do
    case RegentPoints.process_event(id, actor: Store.system()) do
      {:ok, _} -> :ok
      {:error, reason} when job.attempt < job.max_attempts -> {:error, reason}
      {:error, _reason} -> give_up(id)
    end
  end

  defp give_up(id) do
    case Store.event(id) do
      %{processing_status: :pending} = event ->
        RegentPoints.finish_event!(
          event,
          %{processing_status: :rejected, reason_code: "award_failed"},
          actor: Store.system()
        )

        :ok

      _ ->
        :ok
    end
  end
end

defmodule RegentPoints.TallyPeriodsTest do
  use ExUnit.Case, async: false

  alias RegentPoints.TallyPeriods

  setup do
    Application.put_env(:regent_points, :program_id, "tally-periods-test")
    on_exit(fn -> Application.delete_env(:regent_points, :program_id) end)
  end

  # Invariant: a run with nothing to queue still reports that it finished, so the
  # site's "last tally finished" time goes stale only when the daily cron stops.
  test "a run with nothing to queue still reports that it finished" do
    event = [:regent_points, :tally_periods, :finished]
    ref = :telemetry_test.attach_event_handlers(self(), [event])

    assert :ok = TallyPeriods.perform(%Oban.Job{})
    assert_received {^event, ^ref, %{accounts: 0}, %{periods: []}}
  end
end

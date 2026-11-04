defmodule RegentHttp.ErrorSavingTest do
  # Invariant: a crash that cannot be saved never stops later crashes being saved.
  # On regents.sh, 4 Nov, one burst used up the database connections, the save raised
  # inside ErrorTracker's handler, telemetry removed the handler, and crashes went
  # unsaved until the next restart seven hours later.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias RegentHttp.TestRepo

  defmodule OneConnection do
    use Ecto.Repo, otp_app: :regent_http, adapter: Ecto.Adapters.Postgres

    # A save refused at once, so the test does not wait for the queue to give up.
    def default_options(_operation), do: [queue: false]
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(TestRepo, shared: true)

    start_supervised!(
      {OneConnection, TestRepo.config() |> Keyword.delete(:pool) |> Keyword.put(:pool_size, 1)}
    )

    on_exit(fn ->
      Application.put_env(:error_tracker, :repo, TestRepo)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  defp crash(event, metadata) do
    crash =
      try do
        raise "boom"
      rescue
        error -> %{reason: error, stacktrace: __STACKTRACE__}
      end

    # Each request and job is its own process, as it is in production.
    Task.await(
      Task.async(fn -> :telemetry.execute(event, %{duration: 0}, Map.merge(crash, metadata)) end)
    )
  end

  defp saved, do: TestRepo.aggregate(ErrorTracker.Occurrence, :count)

  defp assert_next_one_is_saved(event, metadata) do
    Application.put_env(:error_tracker, :repo, OneConnection)

    # This process holds the pool's only connection while the crash tries to save.
    log = capture_log(fn -> OneConnection.checkout(fn -> crash(event, metadata) end) end)

    assert log =~ "Crash not saved: DBConnection.ConnectionError"
    refute log =~ "has been detached"
    assert saved() == 0

    Application.put_env(:error_tracker, :repo, TestRepo)
    crash(event, metadata)

    assert saved() == 1
  end

  test "a request crash that finds no connection is one warning line, and the next is saved" do
    assert_next_one_is_saved([:phoenix, :router_dispatch, :exception], %{
      conn: Plug.Test.conn(:get, "/"),
      kind: :error
    })
  end

  test "a page crash that finds no connection is one warning line, and the next is saved" do
    assert_next_one_is_saved([:phoenix, :live_view, :mount, :exception], %{kind: :error})
  end

  test "a job crash that finds no connection is one warning line, and the next is saved" do
    assert_next_one_is_saved([:oban, :job, :exception], %{
      state: :discard,
      job: %Oban.Job{worker: "Worker"}
    })
  end
end

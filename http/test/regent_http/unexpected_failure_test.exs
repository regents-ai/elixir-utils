defmodule RegentHttp.UnexpectedFailureTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  import ExUnit.CaptureLog

  alias RegentHttp.UnexpectedFailure

  defmodule Wrapped do
    defexception [:message, errors: []]
  end

  defmodule Cause do
    defexception [:message]
  end

  property "a request line never carries the error's text or the raw request id" do
    check all(
            secret <- map(string(:alphanumeric, min_length: 1), &("secret-" <> &1)),
            request_id <-
              map(string(:alphanumeric, min_length: 1, max_length: 120), &("req-" <> &1))
          ) do
      error = %Wrapped{message: secret, errors: [%Cause{message: secret}]}
      Logger.metadata(request_id: request_id)

      line = capture_log(fn -> UnexpectedFailure.log(%Plug.Conn{}, error) end)

      refute line =~ secret
      refute line =~ request_id
      assert line =~ "class=#{Wrapped}"
      assert line =~ "causes=#{Cause}"
      assert line =~ Base.encode16(:crypto.hash(:sha256, request_id), case: :lower)
    end
  after
    Logger.metadata(request_id: nil)
  end

  test "a request line names at most four causes and returns the conn" do
    conn = %Plug.Conn{}
    error = %Wrapped{errors: List.duplicate(%Cause{}, 9)}

    line = capture_log(fn -> assert UnexpectedFailure.log(conn, error) == conn end)

    assert [causes] = Regex.run(~r/causes=(\S+)/, line, capture: :all_but_first)
    assert length(String.split(causes, ",")) == 4
  end

  test "a job logs once, when it gives up, never on an attempt it will retry" do
    job = %{worker: "Site.Worker", id: 7, attempt: 3}
    error = %Wrapped{message: "secret argument"}

    retried =
      capture_log(fn ->
        UnexpectedFailure.job_failed([], %{}, %{state: :failure, job: job, reason: error}, nil)
      end)

    gave_up =
      capture_log(fn ->
        UnexpectedFailure.job_failed([], %{}, %{state: :discard, job: job, reason: error}, nil)
      end)

    assert retried == ""
    assert gave_up =~ "Job gave up: worker=Site.Worker id=7 attempt=3"
    refute gave_up =~ "secret argument"
  end

  test "attach_jobs listens for Oban's job exceptions once" do
    on_exit(fn -> :telemetry.detach("regent-http-job-gave-up") end)

    assert :ok = UnexpectedFailure.attach_jobs()
    assert {:error, :already_exists} = UnexpectedFailure.attach_jobs()
  end
end

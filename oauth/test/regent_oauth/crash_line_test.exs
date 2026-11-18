defmodule RegentOAuth.CrashLineTest do
  # A failure no check expected was answered 503 and left no trace (18 Nov
  # 2026). It is now logged as one error line naming the endpoint, the
  # exception's module and where it happened, and never a value.
  use RegentOAuth.Case

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias RegentOAuth.Refusal
  alias RegentOAuth.Test.Flow

  @secret "zqsecret9c41"

  defmodule Picky do
    @moduledoc false
    def only(:allowed), do: :ok
  end

  def handle_failure(_event, measurements, metadata, test),
    do: send(test, {:failure, measurements, metadata})

  defp failure(fun) do
    fun.()
  rescue
    exception -> {exception, __STACKTRACE__}
  end

  # The one error line logged; the secret is nowhere in the log.
  defp crash_line(fun) do
    {result, log} = with_log(fun)
    refute log =~ @secret
    assert [[line]] = Regex.scan(~r/oauth failed .*/, log)
    {result, line}
  end

  test "a failure is logged by its exception's module and each frame's function and arity, never a value" do
    # A call that never matched keeps its arguments in its frame, an unknown
    # function's frame has no location, and a missing key's message repeats
    # the list it was looked up in.
    for {fun, function} <- [
          {fn -> Picky.only(@secret) end, "RegentOAuth.CrashLineTest.Picky.only/1"},
          {fn -> apply(Picky, :missing, [@secret, @secret]) end,
           "RegentOAuth.CrashLineTest.Picky.missing/2"},
          {fn -> Keyword.fetch!([token: @secret], :code) end, "Keyword.fetch!/2"}
        ] do
      {exception, stacktrace} = failure(fun)
      assert inspect({exception, stacktrace}) =~ @secret

      {:ok, line} =
        crash_line(fn -> Refusal.crashed(:approve, exception, stacktrace) end)

      assert line =~ "endpoint=approve"
      assert line =~ "exception=#{exception.__struct__}"
      assert line =~ function
      assert line =~ "(crash_line_test.exs:"
      refute line =~ "test/regent_oauth/"
    end
  end

  test "anonymous functions, frames without a location and frames past the fourth keep the line whole" do
    anonymous = fn _token -> :ok end

    stacktrace = [
      {anonymous, [@secret], []},
      {Picky, :"-only/1-fun-0-", [@secret, @secret], [file: ~c"lib/picky.ex", line: 7]},
      {Picky, :only, 1, []},
      {Map, :fetch!, 2, [file: ~c"lib/map.ex", line: 3, error_info: %{module: Exception}]},
      {Picky, :fifth, 0, [file: ~c"lib/picky.ex", line: 9]}
    ]

    {:ok, line} =
      crash_line(fn ->
        Refusal.crashed(:token, %RuntimeError{message: @secret}, stacktrace)
      end)

    assert line =~ "exception=Elixir.RuntimeError"
    assert line =~ "anonymous fn/1 in RegentOAuth.CrashLineTest."
    assert line =~ "anonymous fn/2 in RegentOAuth.CrashLineTest.Picky.only/1 (picky.ex:7)"
    assert line =~ "RegentOAuth.CrashLineTest.Picky.only/1,"
    assert line =~ "Map.fetch!/2 (map.ex:3)"
    refute line =~ "fifth"
  end

  test "a request that fails answers temporarily_unavailable and logs one line for its endpoint" do
    handler = {__MODULE__, self()}

    :telemetry.attach(
      handler,
      [:regent_oauth, :request, :failure],
      &__MODULE__.handle_failure/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    # A body value no JSON encoder takes, whose error repeats it.
    {conn, line} = crash_line(fn -> Flow.post(:token, %{"grant_type" => {@secret}}) end)
    assert conn.status == 503
    assert %{"error" => "temporarily_unavailable"} = Jason.decode!(conn.resp_body)
    assert line =~ "endpoint=token exception=Elixir.Protocol.UndefinedError"
    assert_received {:failure, %{count: 1}, metadata} when metadata == %{}

    # A body the site never read.
    {conn, line} =
      crash_line(fn ->
        conn(:post, "/oauth/connections/revoke")
        |> assign(:subject, "did:privy:sol")
        |> Map.put(:body_params, %Plug.Conn.Unfetched{aspect: :body_params})
        |> RegentOAuth.Consent.revoke_connection()
      end)

    assert conn.status == 503
    assert %{"error" => "temporarily_unavailable"} = Jason.decode!(conn.resp_body)
    assert line =~ "endpoint=revoke_connection exception=Elixir.ArgumentError"
  end
end

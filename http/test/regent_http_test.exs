defmodule RegentHttpTest do
  use ExUnit.Case, async: false

  setup do
    previous_client = Application.get_env(:regent_http, :client)
    previous_pid = Application.get_env(:regent_http, :client_test_pid)

    Application.put_env(:regent_http, :client, __MODULE__.Client)
    Application.put_env(:regent_http, :client_test_pid, self())

    on_exit(fn ->
      restore_env(:client, previous_client)
      restore_env(:client_test_pid, previous_pid)
    end)
  end

  test "adds request timeouts to external calls" do
    assert {:ok, %{status: 200, body: %{}}} = RegentHttp.get("https://example.test")

    assert_receive {:regent_http_request, opts}
    assert opts[:receive_timeout] == 15_000
    assert opts[:connect_options] == [timeout: 5_000]
  end

  test "keeps caller-provided timeouts" do
    assert {:ok, %{status: 200}} =
             RegentHttp.get("https://example.test", receive_timeout: 1_000)

    assert_receive {:regent_http_request, opts}
    assert opts[:receive_timeout] == 1_000
  end

  test "emits a request telemetry event" do
    handler_id = "regent-http-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:regent_http, :request],
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, %{status: 200}} = RegentHttp.get("https://example.test")

    assert_receive {:telemetry, %{duration: duration}, metadata}
    assert is_integer(duration)
    assert metadata.method == :get
    assert metadata.host == "example.test"
    assert metadata.result == 200
  end

  test "keeps sensitive request values out of formatted errors" do
    message =
      RegentHttp.format_error(
        RuntimeError.exception(
          "failed with Bearer sprite-secret and sk_test_123456789 and authorization: token"
        )
      )

    assert message =~ "Bearer [redacted]"
    assert message =~ "sk_test_[redacted]"
    assert message =~ "authorization: [redacted]"
    refute message =~ "sprite-secret"
    refute message =~ "123456789"
  end

  defmodule Client do
    @behaviour RegentHttp

    @impl true
    def request(opts) do
      send(Application.fetch_env!(:regent_http, :client_test_pid), {
        :regent_http_request,
        opts
      })

      {:ok, %{status: 200, body: %{}}}
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:regent_http, key)
  defp restore_env(key, value), do: Application.put_env(:regent_http, key, value)
end

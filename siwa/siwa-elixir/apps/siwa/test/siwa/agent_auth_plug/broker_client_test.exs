defmodule Siwa.AgentAuthPlug.BrokerClientTest do
  use ExUnit.Case, async: true

  alias Siwa.AgentAuthPlug.BrokerClient

  defmodule RecordingHttp do
    def request(opts) do
      send(self(), {:request, opts})
      Process.get(:http_response, {:ok, %{status: 200, body: %{"ok" => true}}})
    end
  end

  @payload %{"method" => "POST", "path" => "/x", "headers" => %{}}

  test "posts the payload to the broker http-verify endpoint with the audience header" do
    assert {:ok, %{status: 200, body: %{"ok" => true}}} =
             BrokerClient.verify_http_request(@payload,
               http: RecordingHttp,
               base_url: "http://siwa.internal:4100/",
               audience: "testapp"
             )

    assert_received {:request, opts}
    assert opts[:method] == :post
    assert opts[:url] == "http://siwa.internal:4100/v1/agent/siwa/http-verify"
    assert opts[:json] == @payload
    assert opts[:headers] == [{"x-siwa-audience", "testapp"}]
    refute Keyword.has_key?(opts, :connect_options)
    refute Keyword.has_key?(opts, :receive_timeout)
  end

  test "passes explicit timeouts through to the http module" do
    BrokerClient.verify_http_request(@payload,
      http: RecordingHttp,
      base_url: "http://siwa.internal:4100",
      audience: "testapp",
      connect_timeout_ms: 2_000,
      receive_timeout_ms: 5_000
    )

    assert_received {:request, opts}
    assert opts[:connect_options] == [timeout: 2_000]
    assert opts[:receive_timeout] == 5_000
  end

  test "returns transport errors unchanged" do
    Process.put(:http_response, {:error, :econnrefused})

    assert {:error, :econnrefused} =
             BrokerClient.verify_http_request(@payload,
               http: RecordingHttp,
               base_url: "http://siwa.internal:4100",
               audience: "testapp"
             )
  end
end

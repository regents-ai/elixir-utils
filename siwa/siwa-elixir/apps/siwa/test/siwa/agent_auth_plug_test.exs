defmodule Siwa.AgentAuthPlugTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Siwa.AgentAuthPlug

  defmodule RecordingClient do
    @behaviour Siwa.AgentAuthPlug.Client

    @impl true
    def verify_http_request(payload, opts) do
      send(self(), {:verify_http_request, payload, opts})
      Process.get(:client_response, {:ok, success_response()})
    end

    def success_response do
      %{
        status: 200,
        body: %{
          "code" => "http_envelope_valid",
          "data" => %{"agent_claims" => %{"token_id" => "77"}}
        }
      }
    end
  end

  defmodule RecordingHooks do
    @behaviour Siwa.AgentAuthPlug.Hooks

    @impl true
    def before_verify(_conn, headers) do
      send(self(), {:before_verify, headers})
      Process.get(:before_verify_result, {:ok, :context})
    end

    @impl true
    def accept(conn, data, context) do
      send(self(), {:accept, data, context})
      {:ok, Plug.Conn.assign(conn, :accepted, true)}
    end

    @impl true
    def deny(conn, deny_meta) do
      send(self(), {:deny, deny_meta})

      conn
      |> Plug.Conn.send_resp(401, "denied")
      |> Plug.Conn.halt()
    end
  end

  defp call(conn, opts \\ []) do
    AgentAuthPlug.call(
      conn,
      Keyword.merge(
        [client: RecordingClient, hooks: RecordingHooks, audience: "testapp"],
        opts
      )
    )
  end

  test "verified envelope flows through accept with before_verify context" do
    conn =
      :post
      |> conn("/v1/things", "{}")
      |> then(&%{&1 | req_headers: [{"X-Agent-Wallet-Address", "0xabc"} | &1.req_headers]})
      |> assign(:raw_body, ~s({"a":1}))
      |> call()

    assert conn.assigns.accepted
    refute conn.halted

    assert_received {:before_verify, %{"x-agent-wallet-address" => "0xabc"}}

    assert_received {:verify_http_request, payload, audience: "testapp"}
    assert payload["method"] == "POST"
    assert payload["path"] == "/v1/things"
    assert payload["body"] == ~s({"a":1})
    assert payload["headers"]["x-agent-wallet-address"] == "0xabc"

    assert_received {:accept, %{"agent_claims" => %{"token_id" => "77"}}, :context}
  end

  test "signed path includes the query string by default and can be path only" do
    :post |> conn("/v1/things?cursor=2", "{}") |> call()
    assert_received {:verify_http_request, %{"path" => "/v1/things?cursor=2"}, _opts}

    :post |> conn("/v1/things?cursor=2", "{}") |> call(signed_path: :path_only)
    assert_received {:verify_http_request, %{"path" => "/v1/things"}, _opts}
  end

  test "body is omitted without a captured raw body unless :always" do
    :post |> conn("/v1/things", "{}") |> call()
    assert_received {:verify_http_request, payload, _opts}
    refute Map.has_key?(payload, "body")

    :post |> conn("/v1/things", "{}") |> call(body: :always)
    assert_received {:verify_http_request, %{"body" => ""}, _opts}
  end

  test "before_verify errors deny without calling the client" do
    Process.put(
      :before_verify_result,
      {:error, %{reason: :missing_agent_headers, source: :request_headers}}
    )

    conn = :post |> conn("/v1/things", "{}") |> call()

    assert conn.halted
    assert conn.status == 401
    assert_received {:deny, %{reason: :missing_agent_headers, source: :request_headers}}
    refute_received {:verify_http_request, _payload, _opts}
  end

  test "non-200 broker responses deny with status and code metadata" do
    Process.put(
      :client_response,
      {:ok, %{status: 401, body: %{"error" => %{"code" => "receipt_invalid"}}}}
    )

    conn = :post |> conn("/v1/things", "{}") |> call()

    assert conn.halted

    assert_received {:deny,
                     %{
                       reason: :siwa_http_401,
                       source: :siwa_http,
                       siwa_status: 401,
                       siwa_code: "receipt_invalid"
                     }}
  end

  test "a 200 response without a valid envelope denies" do
    Process.put(:client_response, {:ok, %{status: 200, body: %{"unexpected" => true}}})

    :post |> conn("/v1/things", "{}") |> call()

    assert_received {:deny, %{reason: :siwa_http_200, source: :siwa_http, siwa_status: 200}}
  end

  test "map-shaped client errors pass through as deny metadata" do
    Process.put(
      :client_response,
      {:error, %{reason: :missing_siwa_internal_url, source: :siwa_config}}
    )

    :post |> conn("/v1/things", "{}") |> call()

    assert_received {:deny, %{reason: :missing_siwa_internal_url, source: :siwa_config}}
  end

  test "transport errors deny as siwa_request_failed with a normalized reason" do
    Process.put(:client_response, {:error, %Mint.TransportError{reason: :econnrefused}})

    :post |> conn("/v1/things", "{}") |> call()

    assert_received {:deny,
                     %{
                       reason: :siwa_request_failed,
                       source: :siwa_http,
                       transport_error: :econnrefused
                     }}
  end

  test "accept errors deny with the hook metadata" do
    defmodule RejectingHooks do
      @behaviour Siwa.AgentAuthPlug.Hooks

      @impl true
      def before_verify(_conn, _headers), do: {:ok, nil}

      @impl true
      def accept(_conn, _data, _context),
        do: {:error, %{reason: :receipt_binding_mismatch, source: :siwa_claims}}

      @impl true
      def deny(conn, deny_meta) do
        send(self(), {:deny, deny_meta})
        Plug.Conn.halt(conn)
      end
    end

    conn = :post |> conn("/v1/things", "{}") |> call(hooks: RejectingHooks)

    assert conn.halted
    assert_received {:deny, %{reason: :receipt_binding_mismatch, source: :siwa_claims}}
  end
end

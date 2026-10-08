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

  defp read_whole_body(conn) do
    {:ok, _body, conn} = AgentAuthPlug.read_body(conn, [], 1_000)
    conn
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
      |> conn("/v1/things", ~s({"a":1}))
      |> then(&%{&1 | req_headers: [{"X-Agent-Wallet-Address", "0xabc"} | &1.req_headers]})
      |> read_whole_body()
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

  test "only the signed headers are forwarded to the sign-in server" do
    :post
    |> conn("/v1/things", "{}")
    |> put_req_header("x-siwa-signature", "sig1=:abc=:")
    |> put_req_header("cookie", "session=person")
    |> put_req_header("authorization", "Bearer person")
    |> call()

    assert_received {:verify_http_request, %{"headers" => headers}, _opts}
    assert headers == %{"x-siwa-signature" => "sig1=:abc=:"}
  end

  test "a signed header sent twice is refused before any hook or sign-in call" do
    conn =
      :post
      |> conn("/v1/things", "{}")
      |> then(&%{&1 | req_headers: [{"x-key-id", "a"}, {"X-Key-Id", "b"} | &1.req_headers]})
      |> call()

    assert conn.halted
    assert_received {:deny, %{reason: :duplicate_proof, source: :siwa_plug}}
    refute_received {:before_verify, _headers}
    refute_received {:verify_http_request, _payload, _opts}
  end

  test "signed_request? tells a signed agent request from a person's" do
    assert :post
           |> conn("/v1/things", "{}")
           |> put_req_header("x-siwa-receipt", "receipt")
           |> AgentAuthPlug.signed_request?()

    refute :post
           |> conn("/v1/things", "{}")
           |> put_req_header("cookie", "session=person")
           |> AgentAuthPlug.signed_request?()
  end

  test "a query string is refused unless the site signs it as part of the path" do
    :get |> conn("/v1/things?cursor=2") |> call()
    assert_received {:deny, %{reason: :unsupported_query, source: :siwa_plug}}
    refute_received {:verify_http_request, _payload, _opts}

    :get |> conn("/v1/things?cursor=2") |> call(query: :signed)
    assert_received {:verify_http_request, %{"path" => "/v1/things?cursor=2"}, _opts}
  end

  test "a body the signature would not cover is refused before any hook" do
    :post |> conn("/v1/things", "{}") |> put_req_header("content-length", "2") |> call()
    assert_received {:deny, %{reason: :missing_signed_body, source: :siwa_plug}}

    :post |> conn("/v1/things", %{"a" => "1"}) |> call()
    assert_received {:deny, %{reason: :missing_signed_body, source: :siwa_plug}}

    refute_received {:before_verify, _headers}
    refute_received {:verify_http_request, _payload, _opts}
  end

  test "read_body keeps a signed body's exact bytes, and a body over the limit is refused" do
    :post
    |> conn("/v1/things", ~s({"a": 1}))
    |> put_req_header("content-length", "8")
    |> read_whole_body()
    |> call()

    assert_received {:verify_http_request, %{"body" => ~s({"a": 1})}, _opts}

    {:more, _chunk, conn} =
      :post |> conn("/v1/things", String.duplicate("a", 11)) |> AgentAuthPlug.read_body([], 10)

    call(conn)
    assert_received {:deny, %{reason: :missing_signed_body, source: :siwa_plug}}
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

  test "non-200 broker responses deny with the broker's status, code, message and hint" do
    Process.put(
      :client_response,
      {:ok,
       %{
         status: 401,
         body: %{
           "error" => %{
             "code" => "receipt_invalid",
             "message" => "Your sign-in has ended.",
             "hint" => "Sign in again."
           }
         }
       }}
    )

    conn = :post |> conn("/v1/things", "{}") |> call()

    assert conn.halted

    assert_received {:deny,
                     %{
                       reason: :siwa_http_401,
                       source: :siwa_http,
                       siwa_status: 401,
                       siwa_code: "receipt_invalid",
                       siwa_message: "Your sign-in has ended.",
                       siwa_hint: "Sign in again."
                     }}
  end

  test "an answer outside 400..599 without a verdict denies as siwa_request_failed" do
    for response <- [
          %{status: 200, body: %{"unexpected" => true}},
          %{status: 302, body: ""},
          %{status: 103, body: ""}
        ] do
      Process.put(:client_response, {:ok, response})

      :post |> conn("/v1/things", "{}") |> call()

      assert_received {:deny, deny_meta}
      assert deny_meta == %{reason: :siwa_request_failed, source: :siwa_http}
    end
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

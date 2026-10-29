defmodule Siwa.AgentAuthPlug.LeaseTest do
  # Reads on a lease are checked on the site, not by the sign-in server, so a
  # mistake here lets a replayed or forged read through without anyone seeing it.
  use ExUnit.Case, async: true

  import Plug.Test

  alias Siwa.{AgentAuthPlug, LocalSigner, Receipt, RequestAuth}
  alias Siwa.AgentAuthPlug.Leases

  @secret "lease-test-secret"
  @audience "testapp"

  defmodule SignInServer do
    # Stands in for siwa-server: the full check with the receipt secret, and a
    # lease ending at the time the test sets when the site asks for one.
    @behaviour Siwa.AgentAuthPlug.Client

    # The audience this site's verify key names at the sign-in server.
    @audience "testapp"

    @impl true
    def verify_http_request(payload) do
      send(self(), {:sign_in_server, payload})

      {:ok, verified} =
        RequestAuth.verify_authenticated_request(
          %{
            method: payload["method"],
            path: payload["path"],
            headers: payload["headers"],
            body_digest: payload["body_digest"]
          },
          secret: "lease-test-secret",
          audience: @audience,
          wallet_audiences: [@audience],
          replay_store: fn _key, _expires -> :ok end
        )

      claims = verified.claims

      data =
        %{
          "walletAddress" => claims["sub"],
          "chainId" => claims["chain_id"],
          "keyId" => claims["key_id"],
          "receiptExpiresAt" => iso8601(claims["exp"]),
          "principal" => %{"audience" => claims["aud"]}
        }
        |> then(fn data ->
          if payload["lease"],
            do: Map.put(data, "leaseExpiresAt", iso8601(Process.get(:lease_until_ms))),
            else: data
        end)

      {:ok, %{status: 200, body: %{"code" => "http_envelope_valid", "data" => data}}}
    end

    defp iso8601(ms), do: ms |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()
  end

  defmodule Hooks do
    @behaviour Siwa.AgentAuthPlug.Hooks

    @impl true
    def before_verify(_conn, _headers), do: {:ok, nil}

    @impl true
    def accept(conn, _data, _context), do: {:ok, Plug.Conn.assign(conn, :accepted, true)}

    @impl true
    def deny(conn, deny_meta) do
      send(self(), {:deny, deny_meta})
      Plug.Conn.halt(conn)
    end
  end

  setup do
    {:ok, signer} = LocalSigner.new()
    receipt = receipt(signer, 3_600_000)
    Process.put(:lease_until_ms, System.system_time(:millisecond) + 600_000)
    %{signer: signer, receipt: receipt}
  end

  test "a read on a lease is checked here, and the same signed read sent again is refused",
       %{signer: signer, receipt: receipt} do
    first = sign("GET", "/updates", nil, receipt, signer)
    assert send_request(first, read_only: true).assigns.accepted
    assert_received {:sign_in_server, %{"lease" => true}}

    second = sign("GET", "/updates", nil, receipt, signer)
    assert send_request(second, read_only: true).assigns.accepted
    refute_received {:sign_in_server, _payload}

    for repeat <- [first, second] do
      assert send_request(repeat, read_only: true).halted
      assert_received {:deny, %{siwa_code: "request_replayed", source: :siwa_lease}}
    end
  end

  test "a read whose body changed after signing is refused on the lease",
       %{signer: signer, receipt: receipt} do
    assert send_request(sign("GET", "/updates", nil, receipt, signer), read_only: true).assigns.accepted

    signed = sign("POST", "/mcp", ~s({"tool":"get_updates"}), receipt, signer)
    assert send_request(%{signed | body: ~s({"tool":"post_message"})}, read_only: true).halted
    assert_received {:deny, %{siwa_code: "http_body_binding_invalid", source: :siwa_lease}}
  end

  test "a read signed by any key but the receipt's wallet is refused on the lease",
       %{signer: signer, receipt: receipt} do
    assert send_request(sign("GET", "/updates", nil, receipt, signer), read_only: true).assigns.accepted

    assert_received {:sign_in_server, _payload}

    {:ok, other} = LocalSigner.new()
    assert send_request(sign("GET", "/updates", nil, receipt, other), read_only: true).halted
    assert_received {:deny, %{siwa_code: "signature_invalid", source: :siwa_lease}}
    refute_received {:sign_in_server, _payload}
  end

  test "a lease ends at its own end or the receipt's, whichever is first",
       %{signer: signer, receipt: receipt} do
    receipt_ends_ms =
      Receipt.verify(receipt, secret: @secret, audience: @audience)
      |> elem(1)
      |> Map.fetch!("exp")

    Process.put(:lease_until_ms, receipt_ends_ms + 600_000)

    assert send_request(sign("GET", "/updates", nil, receipt, signer), read_only: true).assigns.accepted

    assert {:ok, lease} = Leases.fetch(@audience, receipt, receipt_ends_ms - 1)
    assert lease.until_ms == receipt_ends_ms
    assert Leases.fetch(@audience, receipt, receipt_ends_ms) == :none

    request = sign("GET", "/updates", nil, receipt, signer)

    assert RequestAuth.verify_leased_request(
             %{method: "GET", path: "/updates", headers: request.headers, body_digest: nil},
             lease,
             audience: @audience,
             now: DateTime.from_unix!(lease.until_ms, :millisecond)
           ) == {:error, :invalid_receipt}
  end

  test "a request without read_only never uses a lease", %{signer: signer, receipt: receipt} do
    assert send_request(sign("GET", "/updates", nil, receipt, signer), read_only: true).assigns.accepted

    assert_received {:sign_in_server, _payload}

    assert send_request(sign("POST", "/posts", ~s({"text":"hi"}), receipt, signer), []).assigns.accepted

    assert_received {:sign_in_server, payload}
    refute Map.has_key?(payload, "lease")
  end

  defp receipt(signer, ttl_ms) do
    {:ok, receipt} =
      Receipt.create(
        %{
          "typ" => "siwa_wallet_receipt",
          "verified" => "wallet_signature",
          "jti" => "lease-test-#{System.unique_integer([:positive])}",
          "sub" => signer.address,
          "aud" => @audience,
          "chain_id" => 8453,
          "nonce" => "n",
          "key_id" => signer.address
        },
        secret: @secret,
        ttl_ms: ttl_ms
      )

    receipt.token
  end

  defp sign(method, path, body, receipt, signer) do
    {:ok, signed} =
      RequestAuth.sign_authenticated_request(
        %{method: method, path: path, body: body, headers: %{}},
        receipt,
        signer,
        secret: @secret,
        audience: @audience,
        wallet_audiences: [@audience]
      )

    signed
  end

  defp send_request(signed, opts) do
    conn = Enum.reduce(signed.headers, conn(signed.method, signed.path), &put_header/2)

    conn =
      case signed.body do
        nil ->
          conn

        body ->
          conn
          |> Plug.Conn.assign(:raw_body, body)
          |> Plug.Conn.put_private(:siwa_body_complete, true)
      end

    AgentAuthPlug.call(
      conn,
      Keyword.merge([client: SignInServer, hooks: Hooks, audience: @audience], opts)
    )
  end

  defp put_header({name, value}, conn), do: Plug.Conn.put_req_header(conn, name, value)
end

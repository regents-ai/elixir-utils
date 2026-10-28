defmodule Siwa.AgentAuthPlug.DeclaredBodyTest do
  # With `body: :declared` the site never reads the body before the signature is
  # checked, so the signed content-digest is the only thing tying the bytes it
  # later streams to the agent. A mistake here lets unsigned bytes through.
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Plug.Test

  alias Siwa.{AgentAuthPlug, LocalSigner, Receipt, RequestAuth}

  @secret "declared-body-test-secret"
  @audience "testapp"

  defmodule SignInServer do
    # Stands in for siwa-server: the full check with the receipt secret.
    @behaviour Siwa.AgentAuthPlug.Client

    # The audience this site's verify key names at the sign-in server.
    @audience "testapp"

    @impl true
    def verify_http_request(payload) do
      send(self(), {:sign_in_server, payload})

      case RequestAuth.verify_authenticated_request(
             %{
               method: payload["method"],
               path: payload["path"],
               headers: payload["headers"],
               body_digest: payload["body_digest"]
             },
             secret: "declared-body-test-secret",
             audience: @audience,
             wallet_audiences: [@audience],
             replay_store: fn _key, _expires -> :ok end,
             chain_rpcs: Process.get(:chain_rpcs)
           ) do
        {:ok, _verified} ->
          {:ok, %{status: 200, body: %{"code" => "http_envelope_valid", "data" => %{}}}}

        {:error, reason} ->
          {status, code, _message} = Siwa.Contract.refusal(reason)
          {:ok, %{status: status, body: %{"error" => %{"code" => code}}}}
      end
    end
  end

  defmodule Hooks do
    @behaviour Siwa.AgentAuthPlug.Hooks

    @impl true
    def before_verify(_conn, _headers) do
      send(self(), :before_verify)
      {:ok, nil}
    end

    @impl true
    def accept(conn, _data, _context) do
      send(self(), {:accept, conn.assigns[:siwa_body_digest]})
      {:ok, Plug.Conn.assign(conn, :accepted, true)}
    end

    @impl true
    def deny(conn, deny_meta) do
      send(self(), {:deny, deny_meta})
      Plug.Conn.halt(conn)
    end
  end

  defmodule ReadTrap do
    # The test connection's own adapter, telling the test whenever the body is read.
    def read_req_body(state, opts) do
      send(self(), :body_read)
      Plug.Adapters.Test.Conn.read_req_body(state, opts)
    end
  end

  setup do
    {:ok, signer} = LocalSigner.new()
    # Another key's signature could be a smart wallet's; Base says no wallet approves it.
    no_wallet = Siwa.RpcStub.start(Siwa.RpcStub.wallet_answers({true, <<>>}))
    Process.put(:chain_rpcs, %{8453 => [rpc_url: no_wallet]})
    %{signer: signer, receipt: receipt(signer)}
  end

  test "a declared body is verified without reading it, and its digest is handed to the site",
       %{signer: signer, receipt: receipt} do
    body = :crypto.strong_rand_bytes(2_000_000)
    signed = sign("POST", "/repo.git/git-receive-pack", body, receipt, signer)
    declared = signed.headers["content-digest"]

    conn = send_request(signed, body)

    refute_received :body_read
    assert conn.assigns.accepted
    assert conn.assigns.siwa_body_digest == declared
    assert_received {:accept, ^declared}
    assert_received {:sign_in_server, %{"body_digest" => ^declared}}
    # The whole body is still there, for the site to stream.
    assert {:ok, ^body, _conn} = Plug.Conn.read_body(conn, length: 3_000_000)
    assert AgentAuthPlug.declared_body_matches?(:crypto.hash(:sha256, body), declared)
  end

  test "a digest the signature does not cover is refused by the sign-in server",
       %{signer: signer, receipt: receipt} do
    other = Siwa.content_digest_for_body("other bytes")

    # Swapped after signing.
    signed = sign("POST", "/repo.git/git-receive-pack", "pack", receipt, signer)
    assert send_request(put_in(signed.headers["content-digest"], other), "other bytes").halted
    assert_received {:deny, %{siwa_code: "signature_invalid"}}

    # Added to a request signed without a body.
    signed = sign("POST", "/repo.git/git-receive-pack", nil, receipt, signer)
    assert send_request(put_in(signed.headers["content-digest"], other), "other bytes").halted
    assert_received {:deny, %{siwa_code: "http_required_components_missing"}}
    refute_received {:accept, _digest}
  end

  test "a request without one sha-256 content-digest is refused before any hook",
       %{signer: signer, receipt: receipt} do
    signed = sign("POST", "/repo.git/git-receive-pack", "pack", receipt, signer)
    sha256 = Base.encode64(:crypto.hash(:sha256, "pack"))

    assert send_request(%{signed | headers: Map.delete(signed.headers, "content-digest")}, "pack").halted
    assert_received {:deny, %{reason: :missing_content_digest, source: :siwa_plug}}

    for value <- [
          "sha-512=:#{Base.encode64(:crypto.hash(:sha512, "pack"))}:",
          "sha-256=:#{sha256}:, sha-512=:#{Base.encode64(:crypto.hash(:sha512, "pack"))}:",
          "sha-256=:#{sha256}:, sha-256=:#{sha256}:",
          "sha-256=#{sha256}",
          "sha-256=:#{binary_part(sha256, 0, 40)}:",
          "sha-256=:#{Base.encode64(:crypto.hash(:sha256, "pack") <> <<0>>)}:",
          "SHA-256=:#{sha256}:",
          " sha-256=:#{sha256}:",
          "sha-256=:#{sha256}:\n",
          ""
        ] do
      assert send_request(put_in(signed.headers["content-digest"], value), "pack").halted
      assert_received {:deny, %{reason: :invalid_content_digest, source: :siwa_plug}}
    end

    conn =
      signed
      |> request("pack")
      |> then(
        &%{
          &1
          | req_headers: [{"content-digest", signed.headers["content-digest"]} | &1.req_headers]
        }
      )
      |> call()

    assert conn.halted
    assert_received {:deny, %{reason: :duplicate_proof, source: :siwa_plug}}
    refute_received :before_verify
    refute_received {:sign_in_server, _payload}
  end

  # The content-type is not signed, so whoever carries the request can switch it to
  # JSON and swap the body; a parser before the plug would hand the site those bytes.
  test "a body read or parsed before the plug is refused, so the site never acts on it",
       %{signer: signer, receipt: receipt} do
    signed = sign("POST", "/repo.git/git-receive-pack", "pack", receipt, signer)
    swapped = ~s({"ref":"refs/heads/main","force":true})

    for reader <- [[], [body_reader: {AgentAuthPlug, :read_body, [1_000_000]}]] do
      conn =
        signed
        |> request(swapped)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Parsers.call(Plug.Parsers.init([parsers: [:json], json_decoder: Jason] ++ reader))
        |> call()

      assert conn.halted
      assert_received {:deny, %{reason: :declared_body_read, source: :siwa_plug}}
    end

    refute_received {:sign_in_server, _payload}
    refute_received {:accept, _digest}
  end

  # A sha-256's base64 has two spare bits, so four strings decode to the same 32 bytes.
  test "only the one spelling of a sha-256 is a declared digest",
       %{signer: signer, receipt: receipt} do
    sha256 = :crypto.hash(:sha256, "pack")
    {head, <<last, "=">>} = sha256 |> Base.encode64() |> String.split_at(42)
    other = "sha-256=:" <> head <> <<last + 1>> <> "=:"
    assert {:ok, ^sha256} = Base.decode64(head <> <<last + 1>> <> "=")

    refute AgentAuthPlug.declared_body_matches?(sha256, other)

    signed = sign("POST", "/repo.git/git-receive-pack", "pack", receipt, signer)
    assert send_request(put_in(signed.headers["content-digest"], other), "pack").halted
    assert_received {:deny, %{reason: :invalid_content_digest, source: :siwa_plug}}
    refute_received {:sign_in_server, _payload}
  end

  property "streamed bytes match the declared digest only when they are the declared body" do
    check all(
            body <- binary(),
            chunks <- list_of(positive_integer(), max_length: 8),
            other <- binary(),
            other != body
          ) do
      declared = Siwa.content_digest_for_body(body)

      streamed =
        body
        |> split(chunks)
        |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
        |> :crypto.hash_final()

      assert AgentAuthPlug.declared_body_matches?(streamed, declared)
      refute AgentAuthPlug.declared_body_matches?(:crypto.hash(:sha256, other), declared)
    end
  end

  defp split(body, []), do: [body]

  defp split(body, [size | sizes]) when byte_size(body) > size do
    <<chunk::binary-size(size), rest::binary>> = body
    [chunk | split(rest, sizes)]
  end

  defp split(body, _sizes), do: [body]

  defp receipt(signer) do
    {:ok, receipt} =
      Receipt.create(
        %{
          "typ" => "siwa_wallet_receipt",
          "verified" => "wallet_signature",
          "jti" => "declared-test-#{System.unique_integer([:positive])}",
          "sub" => signer.address,
          "aud" => @audience,
          "chain_id" => 8453,
          "nonce" => "n",
          "key_id" => signer.address
        },
        secret: @secret,
        ttl_ms: 3_600_000
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

  # The body sits unread in the connection, as it does before a site's reader runs.
  defp request(signed, body) do
    conn = conn(signed.method, signed.path, body)
    {Plug.Adapters.Test.Conn, state} = conn.adapter

    Enum.reduce(signed.headers, %{conn | adapter: {ReadTrap, state}}, fn {name, value}, conn ->
      Plug.Conn.put_req_header(conn, name, value)
    end)
  end

  defp send_request(signed, body), do: signed |> request(body) |> call()

  defp call(conn) do
    AgentAuthPlug.call(conn,
      client: SignInServer,
      hooks: Hooks,
      audience: @audience,
      body: :declared
    )
  end
end

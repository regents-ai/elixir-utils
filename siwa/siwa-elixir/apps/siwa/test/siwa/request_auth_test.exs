defmodule Siwa.RequestAuthTest.SmartWalletSigner do
  @moduledoc false
  # A smart wallet's signer: its signature is whatever the wallet makes, and
  # only its chain can say whether the wallet approves it.
  defstruct [:address, :signature]

  def sign_message(%__MODULE__{signature: signature}, _message), do: {:ok, signature}
end

defmodule Siwa.RequestAuthTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias Siwa.{LocalSigner, Receipt, RequestAuth}
  alias Siwa.RequestAuthTest.SmartWalletSigner

  @now DateTime.utc_now() |> DateTime.truncate(:second)
  # Plug.Test's host, so a signed request can also be sent through a plug.
  @authority "www.example.com"
  @opts [
    secret: "wallet-test-only",
    audience: "patchbay",
    authorities: [@authority],
    wallet_audiences: ["patchbay"],
    now: @now
  ]

  setup do
    {:ok, signer} = LocalSigner.new()
    {:ok, receipt} = wallet_receipt(signer)
    %{signer: signer, receipt: receipt}
  end

  test "exposes the required authenticated request shape" do
    headers = ~w(
      x-siwa-signature
      x-siwa-signature-input
      x-siwa-receipt
      x-key-id
      x-timestamp
      x-agent-wallet-address
      x-agent-chain-id
    )

    components = ~w(
      @method
      @path
      @authority
      x-siwa-receipt
      x-key-id
      x-timestamp
      x-agent-wallet-address
      x-agent-chain-id
    )

    assert Siwa.required_authenticated_request_headers(nil) == headers

    assert Siwa.required_authenticated_request_headers(Siwa.content_digest_for_body("")) ==
             headers

    assert Siwa.required_authenticated_request_headers(Siwa.content_digest_for_body("{}")) ==
             headers ++ ["content-digest"]

    assert Siwa.required_authenticated_request_components(%{}, nil) == components

    assert Siwa.required_authenticated_request_components(%{}, Siwa.content_digest_for_body("")) ==
             components

    assert Siwa.required_authenticated_request_components(
             %{"Content-Digest" => "sha-256=:YWJj:"},
             nil
           ) == components ++ ["content-digest"]
  end

  test "a signed request with a body carries exactly the forwarded headers", ctx do
    assert Enum.sort(Map.keys(sign(ctx).headers)) == Enum.sort(Siwa.forwarded_headers())
  end

  test "wallet requests need explicit audience opt-in", ctx do
    signed = sign(ctx)

    assert {:error, :wallet_principal_not_allowed} =
             verify(
               signed,
               Keyword.delete(@opts, :wallet_audiences)
             )

    assert {:error, :wallet_principal_not_allowed} =
             verify(
               signed,
               Keyword.put(@opts, :wallet_audiences, ["other"])
             )

    assert {:ok, verified} = verify(signed, @opts)
    assert verified.claims["typ"] == "siwa_wallet_receipt"
    assert verified.claims["verified"] == "wallet_signature"
    assert verified.claims["sub"] == ctx.signer.address
    assert verified.verification_method == :eoa_recovery

    assert {:error, :replayed_request} = verify(signed, @opts)
  end

  # An agent never holds the receipt's secret: Sentinel's signed walks found that
  # the only signer checked it (27 Oct 2026).
  test "an agent signs with its sign-in answer alone, and the verifier accepts it", ctx do
    sign_in = %{
      receipt: ctx.receipt.token,
      key_id: ctx.signer.address,
      wallet_address: ctx.signer.address,
      chain_id: 8453
    }

    assert {:ok, signed} =
             RequestAuth.sign_request(request(), sign_in, ctx.signer, created_at: @now)

    assert {:ok, verified} = verify(signed, @opts)
    assert verified.claims["sub"] == ctx.signer.address
    assert {:error, :replayed_request} = verify(signed, @opts)
  end

  test "signing needs the same audience opt-in", ctx do
    assert {:error, :wallet_principal_not_allowed} =
             RequestAuth.sign_authenticated_request(
               request(),
               ctx.receipt.token,
               ctx.signer,
               Keyword.delete(@opts, :wallet_audiences)
             )
  end

  test "only a complete wallet sign-in receipt signs or verifies a request", ctx do
    for changes <- [
          %{"typ" => "unknown"},
          %{"verified" => nil},
          %{"chain_id" => 0},
          %{"key_id" => "0x" <> String.duplicate("1", 40)},
          %{"jti" => ""}
        ] do
      {:ok, bad} = wallet_receipt(ctx.signer, changes)

      assert {:error, :invalid_receipt} =
               RequestAuth.sign_authenticated_request(request(), bad.token, ctx.signer, @opts)
    end

    signed = sign(ctx)
    [body, mac] = String.split(ctx.receipt.token, ".")
    forged = body <> "x." <> mac

    assert {:error, :invalid_receipt} =
             verify(
               put_in(signed.headers["x-siwa-receipt"], forged),
               @opts
             )
  end

  test "audience, wallet, chain, query, method and exact body stay bound without consuming valid replay",
       ctx do
    signed = sign(ctx)

    assert {:error, :receipt_binding_mismatch} =
             verify(
               signed,
               Keyword.put(@opts, :audience, "other")
             )

    for altered <- [
          %{signed | method: "DELETE"},
          %{signed | path: "/api/agent/payment-intents?mode=other"},
          %{signed | body: "{ \"kind\":\"special_post\"}"},
          put_in(signed.headers["x-agent-chain-id"], "1"),
          put_in(signed.headers["x-agent-wallet-address"], "0x" <> String.duplicate("1", 40))
        ] do
      assert {:error, _} = verify(altered, @opts)
    end

    assert {:ok, _} = verify(signed, @opts)
  end

  test "a request is accepted only at one of the site's hosts, and only the one it was signed for",
       ctx do
    signed = sign(ctx)
    elsewhere = %{signed | authority: "other.example"}
    no_wallet = Siwa.RpcStub.start(Siwa.RpcStub.wallet_answers({true, <<>>}))

    assert {:error, :authority_mismatch} = verify(elsewhere, @opts)

    assert {:error, :signature_invalid} =
             verify(
               elsewhere,
               Keyword.merge(@opts,
                 authorities: ["other.example", @authority],
                 chain_rpcs: %{8453 => [rpc_url: no_wallet]}
               )
             )

    assert {:ok, _} = verify(signed, @opts)

    assert {:error, :authority_required} =
             RequestAuth.sign_authenticated_request(
               Map.delete(request(), :authority),
               ctx.receipt.token,
               ctx.signer,
               @opts
             )
  end

  test "invalid signatures cannot burn a wallet's valid request", ctx do
    {:ok, other} = LocalSigner.new()
    wrong = sign(%{ctx | signer: other}, nonce: "same-nonce")
    valid = sign(ctx, nonce: "same-nonce")
    # Another key's signature could be a smart wallet's; Base says no wallet approves it.
    no_wallet = Siwa.RpcStub.start(Siwa.RpcStub.wallet_answers({true, <<>>}))

    assert {:error, :signature_invalid} =
             verify(
               wrong,
               Keyword.put(@opts, :chain_rpcs, %{8453 => [rpc_url: no_wallet]})
             )

    assert {:ok, _} = verify(valid, @opts)
  end

  test "a smart wallet's request is its answer on its chain, and a failed lookup keeps the request",
       ctx do
    smart = %SmartWalletSigner{
      address: "0x452f678f6e588069d1aef38d3d519567aa1014a4",
      signature: "0x" <> String.duplicate("ab", 224)
    }

    {:ok, receipt} = wallet_receipt(smart)
    signed = sign(%{ctx | signer: smart, receipt: receipt})
    assert byte_size(signed.headers["x-siwa-signature"]) > 90

    assert {:error, :signature_lookup_failed} =
             verify(signed, @opts)

    approves =
      Siwa.RpcStub.start(Siwa.RpcStub.wallet_answers({true, Siwa.RpcStub.erc1271_approval()}))

    assert {:ok, verified} =
             verify(
               signed,
               Keyword.put(@opts, :chain_rpcs, %{8453 => [rpc_url: approves]})
             )

    assert verified.address == smart.address
    assert verified.verification_method == :erc1271
  end

  # A smart wallet's approval holds only on the chain that gave it: a wallet
  # signed in on Ethereum is asked on Ethereum, never on Base.
  test "a smart wallet signed in on Ethereum is asked on Ethereum", ctx do
    smart = %SmartWalletSigner{
      address: "0x452f678f6e588069d1aef38d3d519567aa1014a4",
      signature: "0x" <> String.duplicate("ab", 224)
    }

    {:ok, receipt} = wallet_receipt(smart, %{"chain_id" => 1})
    signed = sign(%{ctx | signer: smart, receipt: receipt})

    approves =
      Siwa.RpcStub.start(Siwa.RpcStub.wallet_answers({true, Siwa.RpcStub.erc1271_approval()}))

    assert {:error, :signature_lookup_failed} =
             verify(
               signed,
               Keyword.put(@opts, :chain_rpcs, %{8453 => [rpc_url: approves]})
             )

    assert {:ok, verified} =
             verify(
               signed,
               Keyword.put(@opts, :chain_rpcs, %{1 => [rpc_url: approves]})
             )

    assert verified.claims["chain_id"] == 1
    assert verified.verification_method == :erc1271
  end

  test "expired receipts and request windows are rejected", ctx do
    signed = sign(ctx)

    assert {:error, :invalid_receipt} =
             verify(
               signed,
               Keyword.put(@opts, :now, DateTime.add(@now, 1801))
             )

    assert {:error, :request_expired} =
             verify(
               signed,
               Keyword.put(@opts, :now, DateTime.add(@now, 121))
             )
  end

  test "a request older than the freshness window is refused", ctx do
    assert {:error, :request_too_old} =
             verify(
               sign(ctx, expires_in_seconds: 300),
               Keyword.put(@opts, :now, DateTime.add(@now, 301))
             )
  end

  test "a request that lasts longer than the signature tolerance is refused", ctx do
    assert {:error, :request_lifetime_too_long} =
             verify(sign(ctx, expires_in_seconds: 301), @opts)

    assert {:error, :request_lifetime_too_long} =
             verify(
               sign(ctx, expires_in_seconds: 601),
               Keyword.put(@opts, :signature_tolerance_seconds, 600)
             )

    assert {:ok, _} = verify(sign(ctx, expires_in_seconds: 300), @opts)
  end

  test "a used request stays used until it expires", ctx do
    parent = self()

    store = fn _key, kept_until ->
      send(parent, {:kept_until, kept_until})
      :ok
    end

    assert {:ok, _} =
             verify(
               sign(ctx, expires_in_seconds: 300),
               Keyword.merge(@opts, now: DateTime.add(@now, 30), replay_store: store)
             )

    assert_receive {:kept_until, kept_until}
    assert kept_until == DateTime.to_unix(@now) + 300
  end

  test "a long-lived request is used once across machines with different tolerances", ctx do
    {:ok, entries} = Agent.start_link(fn -> %{} end)

    store = fn key, kept_until ->
      Agent.get_and_update(entries, fn kept ->
        if Map.has_key?(kept, key),
          do: {{:error, :replayed_request}, kept},
          else: {:ok, Map.put(kept, key, kept_until)}
      end)
    end

    at = fn seconds, tolerance ->
      Keyword.merge(@opts,
        now: DateTime.add(@now, seconds),
        signature_tolerance_seconds: tolerance,
        replay_store: store
      )
    end

    signed = sign(ctx, expires_in_seconds: 600)

    # A machine with the 300-second tolerance refuses it, so none keeps its entry
    # only until created + 301 and leaves it for a 600-second machine to take again.
    assert {:error, :request_lifetime_too_long} = verify(signed, at.(10, 300))
    assert {:ok, _} = verify(signed, at.(10, 600))

    # Entries that ended by created + 400 are cleared; this one lasts to created + 600.
    sweep_at = DateTime.to_unix(@now) + 400
    Agent.update(entries, &Map.reject(&1, fn {_key, kept_until} -> kept_until <= sweep_at end))

    assert {:error, :replayed_request} = verify(signed, at.(400, 600))
  end

  test "a request created beyond the clock-skew tolerance is refused", ctx do
    assert {:error, :request_not_yet_valid} =
             verify(
               sign(ctx, created_at: DateTime.add(@now, 600)),
               @opts
             )
  end

  test "an envelope is expired at its replay retention boundary", ctx do
    assert {:error, :request_expired} =
             verify(
               sign(ctx),
               Keyword.put(@opts, :now, DateTime.add(@now, 120))
             )
  end

  test "missing signature coverage and malformed envelopes fail before replay", ctx do
    signed = sign(ctx)

    for headers <- [
          Map.delete(signed.headers, "x-siwa-signature"),
          Map.delete(signed.headers, "x-key-id"),
          Map.delete(signed.headers, "content-digest"),
          Map.put(signed.headers, "x-siwa-signature", "malformed"),
          Map.update!(
            signed.headers,
            "x-siwa-signature-input",
            &String.replace(&1, ~s( "x-agent-chain-id"), "")
          ),
          Map.update!(signed.headers, "x-siwa-signature-input", &(&1 <> ";created=1"))
        ] do
      assert {:error, _} =
               verify(%{signed | headers: headers}, @opts)
    end

    assert {:ok, _} = verify(signed, @opts)
  end

  test "requests which passed an earlier clock check cannot consume expired replay entries",
       ctx do
    earlier = DateTime.utc_now() |> DateTime.add(-10) |> DateTime.truncate(:second)

    opts =
      Keyword.merge(@opts,
        now: earlier,
        created_at: earlier,
        expires_at: DateTime.add(earlier, 1)
      )

    {:ok, signed} =
      RequestAuth.sign_authenticated_request(request(), ctx.receipt.token, ctx.signer, opts)

    # The verifier sees the earlier clock, as if it paused after its initial check.
    # The atomic store sees the real later clock and must refuse every copy.
    results =
      1..4
      |> Task.async_stream(fn _ -> verify(signed, opts) end)
      |> Enum.to_list()

    assert results == List.duplicate({:ok, {:error, :request_expired}}, 4)
  end

  test "simultaneous identical wallet envelopes have one replay winner", ctx do
    signed = sign(ctx)

    results =
      1..8
      |> Task.async_stream(fn _ -> verify(signed, @opts) end)
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :replayed_request})) == 7
  end

  test "replay storage failure refuses the request", ctx do
    parent = self()

    store = fn key, expiry ->
      send(parent, {:key, key, expiry})
      {:error, :replay_store_unavailable}
    end

    assert {:error, :replay_store_unavailable} =
             verify(
               sign(ctx),
               Keyword.put(@opts, :replay_store, store)
             )

    assert_receive {:key, key, expiry}
    assert expiry == DateTime.to_unix(@now) + 120

    assert [
             "wallet",
             address,
             8453,
             "patchbay",
             _,
             "POST",
             "/api/agent/payment-intents?mode=create",
             _
           ] = Jason.decode!(key)

    assert address == String.downcase(ctx.signer.address)
  end

  test "the same nonce is independent across wallet audiences", ctx do
    assert {:ok, _} = verify(sign(ctx, nonce: "shared"), @opts)

    {:ok, other} = wallet_receipt(ctx.signer, %{"aud" => "other"})
    other_opts = Keyword.merge(@opts, audience: "other", wallet_audiences: ["other"])
    signed = sign(%{ctx | receipt: other}, Keyword.merge(other_opts, nonce: "shared"))
    assert {:ok, _} = verify(signed, other_opts)
  end

  test "wallet envelopes also support bodyless owner recovery", ctx do
    {:ok, signed} =
      RequestAuth.sign_authenticated_request(
        %{request() | method: "GET", path: "/api/agent/payment-intents/owned-id", body: nil},
        ctx.receipt.token,
        ctx.signer,
        Keyword.put(@opts, :created_at, @now)
      )

    assert {:ok, _} = verify(signed, @opts)
    refute Map.has_key?(signed.headers, "content-digest")
  end

  # No body and an empty body are one request (RFC 9112 6.3, RFC 9530 6.3): the
  # body a request declares, its content-digest or the empty body without one,
  # must be the body the site read, the digest it reports or the empty body
  # without one. The lease check is the sign-in server's own.
  test "a request is accepted only when the body it declares is the body the site read", ctx do
    empty = Siwa.content_digest_for_body("")
    x = Siwa.content_digest_for_body("x")
    y = Siwa.content_digest_for_body("y")
    # What the site reports: none, the empty body, X and Y.
    reports = [nil, empty, x, y]

    requests = %{
      absent: sign_body(ctx, nil),
      empty: sign_digest(ctx, empty),
      x: sign_body(ctx, "x")
    }

    expected = [
      absent: [:ok, :ok, :missing_signed_headers, :missing_signed_headers],
      empty: [:ok, :ok, :content_digest_mismatch, :content_digest_mismatch],
      x: [:content_digest_mismatch, :content_digest_mismatch, :ok, :content_digest_mismatch]
    ]

    used = fn _key, _expires -> :ok end

    checks = [
      full:
        &RequestAuth.verify_authenticated_request(&1, Keyword.put(@opts, :replay_store, used)),
      lease:
        &RequestAuth.verify_leased_request(&1, lease(ctx),
          audience: "patchbay",
          now: @now,
          replay_store: used
        )
    ]

    for {check, verify} <- checks do
      outcomes =
        for {header, _outcomes} <- expected do
          {header,
           Enum.map(reports, fn report ->
             case verify.(Map.put(requests[header], :body_digest, report)) do
               {:ok, _verified} -> :ok
               {:error, reason} -> reason
             end
           end)}
        end

      assert {check, outcomes} == {check, expected}
    end
  end

  test "no body and the empty body's digest are one request with one single-use key", ctx do
    parent = self()

    store = fn key, _expires ->
      send(parent, {:replay_key, key})
      :ok
    end

    empty = Siwa.content_digest_for_body("")

    for signed <- [sign_body(ctx, nil, nonce: "one"), sign_digest(ctx, empty, nonce: "one")],
        report <- [nil, empty] do
      assert {:ok, _verified} =
               RequestAuth.verify_authenticated_request(
                 Map.put(signed, :body_digest, report),
                 Keyword.put(@opts, :replay_store, store)
               )
    end

    keys =
      for _spelling <- 1..4 do
        assert_received {:replay_key, key}
        key
      end

    assert [_one_key] = Enum.uniq(keys)
  end

  test "an empty body signs as no body, and verifies when the site reads zero bytes", ctx do
    signed = sign_body(ctx, "", nonce: "empty")

    assert signed.headers == sign_body(ctx, nil, nonce: "empty").headers
    assert {:ok, _verified} = verify(signed, @opts)
  end

  test "the plug accepts a request body preserved in conn.private", ctx do
    signed = sign(ctx)

    conn =
      Enum.reduce(
        signed.headers,
        conn(signed.method, signed.path, signed.body) |> put_private(:raw_body, signed.body),
        fn {key, value}, acc -> put_req_header(acc, key, value) end
      )

    result = Siwa.Plug.call(conn, @opts)

    refute result.halted
    assert result.assigns.siwa_agent.address == ctx.signer.address
  end

  # A verifier is given the digest of the body the site read, never the body.
  defp verify(request, opts),
    do:
      RequestAuth.verify_authenticated_request(
        Map.put(request, :body_digest, RequestAuth.content_digest_for_body(request.body)),
        opts
      )

  defp request,
    do: %{
      method: "POST",
      path: "/api/agent/payment-intents?mode=create",
      authority: @authority,
      body: ~s({"kind":"special_post"}),
      headers: %{}
    }

  defp sign(ctx, extra \\ []), do: sign_body(ctx, request().body, extra)

  defp sign_body(ctx, body, extra \\ []) do
    opts = @opts |> Keyword.put(:created_at, @now) |> Keyword.merge(extra)

    {:ok, signed} =
      RequestAuth.sign_authenticated_request(
        %{request() | body: body},
        ctx.receipt.token,
        ctx.signer,
        opts
      )

    signed
  end

  # The library signs an empty body as none, so a request covering the empty
  # body's digest is signed here, over a body's signature-input.
  defp sign_digest(ctx, content_digest, extra \\ []) do
    signed = sign_body(ctx, "x", extra)
    headers = Map.put(signed.headers, "content-digest", content_digest)
    {:ok, message} = RequestAuth.signing_message(%{signed | headers: headers})
    {:ok, "0x" <> signature} = LocalSigner.sign_message(ctx.signer, message)
    signature = signature |> Base.decode16!(case: :mixed) |> Base.encode64()

    %{signed | body: nil, headers: Map.put(headers, "x-siwa-signature", "sig1=:#{signature}:")}
  end

  defp lease(ctx) do
    %{
      receipt: ctx.receipt.token,
      claims: %{
        "sub" => ctx.signer.address,
        "key_id" => ctx.signer.address,
        "chain_id" => 8453,
        "aud" => "patchbay"
      },
      authority: @authority,
      until_ms: DateTime.to_unix(@now, :millisecond) + 60_000
    }
  end

  defp wallet_receipt(signer, changes \\ %{}) do
    payload = %{
      "typ" => "siwa_wallet_receipt",
      "verified" => "wallet_signature",
      "jti" => "wallet-fixture",
      "sub" => signer.address,
      "aud" => "patchbay",
      "chain_id" => 8453,
      "nonce" => "fixture-nonce",
      "key_id" => signer.address
    }

    Receipt.create(Map.merge(payload, changes), @opts)
  end
end

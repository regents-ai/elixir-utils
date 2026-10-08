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
  @opts [
    secret: "wallet-test-only",
    audience: "patchbay",
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
      x-siwa-receipt
      x-key-id
      x-timestamp
      x-agent-wallet-address
      x-agent-chain-id
    )

    assert Siwa.required_authenticated_request_headers(nil) == headers
    assert Siwa.required_authenticated_request_headers("{}") == headers ++ ["content-digest"]
    assert Siwa.required_authenticated_request_components(%{}, nil) == components

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
             RequestAuth.verify_authenticated_request(
               signed,
               Keyword.delete(@opts, :wallet_audiences)
             )

    assert {:error, :wallet_principal_not_allowed} =
             RequestAuth.verify_authenticated_request(
               signed,
               Keyword.put(@opts, :wallet_audiences, ["other"])
             )

    assert {:ok, verified} = RequestAuth.verify_authenticated_request(signed, @opts)
    assert verified.claims["typ"] == "siwa_wallet_receipt"
    assert verified.claims["verified"] == "wallet_signature"
    assert verified.claims["sub"] == ctx.signer.address
    assert verified.verification_method == :eoa_recovery

    assert {:error, :replayed_request} = RequestAuth.verify_authenticated_request(signed, @opts)
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
             RequestAuth.verify_authenticated_request(
               put_in(signed.headers["x-siwa-receipt"], forged),
               @opts
             )
  end

  test "audience, wallet, chain, query, method and exact body stay bound without consuming valid replay",
       ctx do
    signed = sign(ctx)

    assert {:error, :receipt_binding_mismatch} =
             RequestAuth.verify_authenticated_request(
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
      assert {:error, _} = RequestAuth.verify_authenticated_request(altered, @opts)
    end

    assert {:ok, _} = RequestAuth.verify_authenticated_request(signed, @opts)
  end

  test "invalid signatures cannot burn a wallet's valid request", ctx do
    {:ok, other} = LocalSigner.new()
    wrong = sign(%{ctx | signer: other}, nonce: "same-nonce")
    valid = sign(ctx, nonce: "same-nonce")
    # Another key's signature could be a smart wallet's; Base says no wallet approves it.
    no_wallet = Siwa.RpcStub.start(Siwa.RpcStub.wallet_answers({true, <<>>}))

    assert {:error, :signature_invalid} =
             RequestAuth.verify_authenticated_request(
               wrong,
               Keyword.put(@opts, :chain_rpcs, %{8453 => [rpc_url: no_wallet]})
             )

    assert {:ok, _} = RequestAuth.verify_authenticated_request(valid, @opts)
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
             RequestAuth.verify_authenticated_request(signed, @opts)

    approves =
      Siwa.RpcStub.start(Siwa.RpcStub.wallet_answers({true, Siwa.RpcStub.erc1271_approval()}))

    assert {:ok, verified} =
             RequestAuth.verify_authenticated_request(
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
             RequestAuth.verify_authenticated_request(
               signed,
               Keyword.put(@opts, :chain_rpcs, %{8453 => [rpc_url: approves]})
             )

    assert {:ok, verified} =
             RequestAuth.verify_authenticated_request(
               signed,
               Keyword.put(@opts, :chain_rpcs, %{1 => [rpc_url: approves]})
             )

    assert verified.claims["chain_id"] == 1
    assert verified.verification_method == :erc1271
  end

  test "expired receipts and request windows are rejected", ctx do
    signed = sign(ctx)

    assert {:error, :invalid_receipt} =
             RequestAuth.verify_authenticated_request(
               signed,
               Keyword.put(@opts, :now, DateTime.add(@now, 1801))
             )

    assert {:error, :request_expired} =
             RequestAuth.verify_authenticated_request(
               signed,
               Keyword.put(@opts, :now, DateTime.add(@now, 121))
             )
  end

  test "a request older than the freshness window is refused", ctx do
    assert {:error, :request_too_old} =
             RequestAuth.verify_authenticated_request(
               sign(ctx, expires_in_seconds: 600),
               Keyword.put(@opts, :now, DateTime.add(@now, 360))
             )
  end

  test "a request created beyond the clock-skew tolerance is refused", ctx do
    assert {:error, :request_not_yet_valid} =
             RequestAuth.verify_authenticated_request(
               sign(ctx, created_at: DateTime.add(@now, 600)),
               @opts
             )
  end

  test "an envelope is expired at its replay retention boundary", ctx do
    assert {:error, :request_expired} =
             RequestAuth.verify_authenticated_request(
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
               RequestAuth.verify_authenticated_request(%{signed | headers: headers}, @opts)
    end

    assert {:ok, _} = RequestAuth.verify_authenticated_request(signed, @opts)
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
      |> Task.async_stream(fn _ -> RequestAuth.verify_authenticated_request(signed, opts) end)
      |> Enum.to_list()

    assert results == List.duplicate({:ok, {:error, :request_expired}}, 4)
  end

  test "simultaneous identical wallet envelopes have one replay winner", ctx do
    signed = sign(ctx)

    results =
      1..8
      |> Task.async_stream(fn _ -> RequestAuth.verify_authenticated_request(signed, @opts) end)
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
             RequestAuth.verify_authenticated_request(
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
    assert {:ok, _} = RequestAuth.verify_authenticated_request(sign(ctx, nonce: "shared"), @opts)

    {:ok, other} = wallet_receipt(ctx.signer, %{"aud" => "other"})
    other_opts = Keyword.merge(@opts, audience: "other", wallet_audiences: ["other"])
    signed = sign(%{ctx | receipt: other}, Keyword.merge(other_opts, nonce: "shared"))
    assert {:ok, _} = RequestAuth.verify_authenticated_request(signed, other_opts)
  end

  test "wallet envelopes also support bodyless owner recovery", ctx do
    {:ok, signed} =
      RequestAuth.sign_authenticated_request(
        %{request() | method: "GET", path: "/api/agent/payment-intents/owned-id", body: nil},
        ctx.receipt.token,
        ctx.signer,
        Keyword.put(@opts, :created_at, @now)
      )

    assert {:ok, _} = RequestAuth.verify_authenticated_request(signed, @opts)
    refute Map.has_key?(signed.headers, "content-digest")
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

  defp request,
    do: %{
      method: "POST",
      path: "/api/agent/payment-intents?mode=create",
      body: ~s({"kind":"special_post"}),
      headers: %{}
    }

  defp sign(ctx, extra \\ []) do
    opts = @opts |> Keyword.put(:created_at, @now) |> Keyword.merge(extra)

    {:ok, signed} =
      RequestAuth.sign_authenticated_request(request(), ctx.receipt.token, ctx.signer, opts)

    signed
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

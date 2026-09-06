defmodule Siwa.WalletRequestAuthTest do
  use ExUnit.Case, async: true

  alias Siwa.{LocalSigner, Receipt, RequestAuth}

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

  test "wallet requests need explicit audience opt-in and never assert registration", ctx do
    signed = sign(ctx)
    refute Map.has_key?(signed.headers, "x-agent-token-id")
    refute Map.has_key?(signed.headers, "x-agent-registry-address")

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
    refute Map.has_key?(verified.claims, "token_id")

    assert {:error, :replayed_request} = RequestAuth.verify_authenticated_request(signed, @opts)
  end

  test "an agent-only signer cannot accidentally create wallet envelopes", ctx do
    assert {:error, :wallet_principal_not_allowed} =
             RequestAuth.sign_authenticated_request(
               request(),
               ctx.receipt.token,
               ctx.signer,
               Keyword.delete(@opts, :wallet_audiences)
             )
  end

  test "signed receipt type and proof select the principal, never omitted registry fields", ctx do
    for changes <- [
          %{"typ" => "siwa_receipt"},
          %{"typ" => "unknown"},
          %{"verified" => "onchain"},
          %{"registry_address" => nil},
          %{"token_id" => "1"},
          %{"chain_id" => 1},
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
          put_in(signed.headers["x-agent-wallet-address"], "0x" <> String.duplicate("1", 40)),
          put_in(signed.headers["x-agent-registry-address"], "0x" <> String.duplicate("2", 40)),
          put_in(signed.headers["x-agent-token-id"], "1")
        ] do
      assert {:error, _} = RequestAuth.verify_authenticated_request(altered, @opts)
    end

    assert {:ok, _} = RequestAuth.verify_authenticated_request(signed, @opts)
  end

  test "invalid signatures cannot burn a wallet's valid request", ctx do
    {:ok, other} = LocalSigner.new()
    wrong = sign(%{ctx | signer: other}, nonce: "same-nonce")
    valid = sign(ctx, nonce: "same-nonce")
    assert {:error, :signature_invalid} = RequestAuth.verify_authenticated_request(wrong, @opts)
    assert {:ok, _} = RequestAuth.verify_authenticated_request(valid, @opts)
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
          Map.delete(signed.headers, "signature"),
          Map.delete(signed.headers, "x-key-id"),
          Map.delete(signed.headers, "content-digest"),
          Map.put(signed.headers, "signature", "malformed"),
          Map.update!(
            signed.headers,
            "signature-input",
            &String.replace(&1, ~s( "x-agent-chain-id"), "")
          ),
          Map.update!(signed.headers, "signature-input", &(&1 <> ";created=1"))
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

    store = fn key, _expiry ->
      send(parent, {:key, key})
      {:error, :replay_store_unavailable}
    end

    assert {:error, :replay_store_unavailable} =
             RequestAuth.verify_authenticated_request(
               sign(ctx),
               Keyword.put(@opts, :replay_store, store)
             )

    assert_receive {:key, key}

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

  test "the same nonce is independent across registered agent and wallet principals and wallet audiences",
       ctx do
    {:ok, agent} =
      wallet_receipt(ctx.signer, %{
        "typ" => "siwa_receipt",
        "verified" => "onchain",
        "registry_address" => "0x" <> String.duplicate("2", 40),
        "token_id" => "1"
      })

    assert {:ok, _} =
             RequestAuth.verify_authenticated_request(
               sign(%{ctx | receipt: agent}, nonce: "shared"),
               @opts
             )

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

defmodule RegentPrivyTest do
  use ExUnit.Case, async: true

  @app_id "test-privy-app"
  @now 1_750_000_000

  setup_all do
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_meta, private_pem} = JOSE.JWK.to_pem(jwk)
    {_meta, public_pem} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()

    {:ok, private_pem: private_pem, public_pem: public_pem}
  end

  defp sign(claims, private_pem) do
    private_jwk = JOSE.JWK.from_pem(private_pem)

    {_meta, token} =
      private_jwk
      |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims)
      |> JOSE.JWS.compact()

    token
  end

  defp base_claims do
    %{
      "iss" => "privy.io",
      "aud" => @app_id,
      "sub" => "did:privy:user-1",
      "iat" => @now - 10,
      "exp" => @now + 3_600
    }
  end

  defp verify(token, ctx, opts \\ []) do
    RegentPrivy.verify_token(
      token,
      Keyword.merge([app_id: @app_id, verification_key: ctx.public_pem, now: @now], opts)
    )
  end

  test "verifies a valid token and returns claims and subject", ctx do
    token = sign(base_claims(), ctx.private_pem)

    assert {:ok,
            %{
              privy_user_id: "did:privy:user-1",
              wallet_address: nil,
              wallet_addresses: [],
              claims: %{"iss" => "privy.io"}
            }} = verify(token, ctx)
  end

  test "extracts normalized wallets and names the most recently verified one", ctx do
    linked_accounts =
      Jason.encode!([
        %{
          "type" => "wallet",
          "address" => " 0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266 ",
          "lv" => 1_700_000_000
        },
        %{
          "type" => "wallet",
          "address" => "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
          "lv" => 1_700_000_100
        },
        %{
          "type" => "wallet",
          "address" => "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
          "lv" => 1_700_000_200
        },
        %{"type" => "email", "value" => "a@b.c", "lv" => 1_700_000_300},
        %{"type" => "wallet", "address" => "not-a-wallet", "lv" => 1_700_000_400},
        %{"type" => "wallet", "address" => "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"}
      ])

    token =
      base_claims()
      |> Map.put("linked_accounts", linked_accounts)
      |> sign(ctx.private_pem)

    assert {:ok,
            %{
              wallet_address: "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
              wallet_addresses: [
                "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
                "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"
              ]
            }} = verify(token, ctx)
  end

  test "rejects malformed linked_accounts payloads", ctx do
    token =
      base_claims()
      |> Map.put("linked_accounts", "{not json")
      |> sign(ctx.private_pem)

    assert {:error, :invalid_linked_accounts} = verify(token, ctx)
  end

  test "accepts the app id within an audience list", ctx do
    token = base_claims() |> Map.put("aud", ["other", @app_id]) |> sign(ctx.private_pem)
    assert {:ok, _verified} = verify(token, ctx)
  end

  test "rejects a wrong issuer, audience, or missing subject", ctx do
    token = base_claims() |> Map.put("iss", "evil.example") |> sign(ctx.private_pem)
    assert {:error, :invalid_issuer} = verify(token, ctx)

    token = base_claims() |> Map.put("aud", "another-app") |> sign(ctx.private_pem)
    assert {:error, :invalid_audience} = verify(token, ctx)

    token = base_claims() |> Map.delete("sub") |> sign(ctx.private_pem)
    assert {:error, :invalid_subject} = verify(token, ctx)
  end

  test "rejects expired, not-yet-valid, and future-issued tokens", ctx do
    token = base_claims() |> Map.put("exp", @now - 1) |> sign(ctx.private_pem)
    assert {:error, :token_expired} = verify(token, ctx)

    token = base_claims() |> Map.put("nbf", @now + 30) |> sign(ctx.private_pem)
    assert {:error, :token_not_yet_valid} = verify(token, ctx)

    token = base_claims() |> Map.put("iat", @now + 120) |> sign(ctx.private_pem)
    assert {:error, :token_issued_in_future} = verify(token, ctx)

    token = base_claims() |> Map.put("iat", @now + 30) |> sign(ctx.private_pem)
    assert {:ok, _verified} = verify(token, ctx)

    token = base_claims() |> Map.delete("exp") |> sign(ctx.private_pem)
    assert {:error, :invalid_token} = verify(token, ctx)
  end

  test "rejects tokens signed with a different key", ctx do
    other_jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_meta, other_pem} = JOSE.JWK.to_pem(other_jwk)
    token = sign(base_claims(), other_pem)

    assert {:error, :token_verification_failed} = verify(token, ctx)
  end

  test "rejects garbage tokens and unusable keys", ctx do
    assert {:error, :token_verification_failed} = verify("not-a-jwt", ctx)

    token = sign(base_claims(), ctx.private_pem)

    assert {:error, :token_verification_failed} =
             verify(token, ctx, verification_key: "not a pem")

    assert {:error, :invalid_verification_key} =
             verify(token, ctx, verification_key: :not_a_binary)

    assert {:error, :invalid_token} =
             RegentPrivy.verify_token(nil, app_id: "x", verification_key: "y")
  end

  test "extracts a typed X account", ctx do
    linked_accounts =
      Jason.encode!([
        %{
          "type" => "twitter_oauth",
          "subject" => "twitter-user-42",
          "username" => "regent",
          "name" => "Regent"
        }
      ])

    token =
      base_claims()
      |> Map.put("linked_accounts", linked_accounts)
      |> sign(ctx.private_pem)

    assert {:ok,
            %{
              linked_socials: [
                %{
                  provider: :x,
                  subject: "twitter-user-42",
                  username: "regent",
                  display_name: "Regent"
                }
              ]
            }} = verify(token, ctx)
  end

  test "extracts a typed GitHub account", ctx do
    linked_accounts =
      Jason.encode!([
        %{
          "type" => "github_oauth",
          "subject" => "github-user-7",
          "username" => "regents-ai"
        }
      ])

    token =
      base_claims()
      |> Map.put("linked_accounts", linked_accounts)
      |> sign(ctx.private_pem)

    assert {:ok,
            %{
              linked_socials: [
                %{
                  provider: :github,
                  subject: "github-user-7",
                  username: "regents-ai",
                  display_name: nil
                }
              ]
            }} = verify(token, ctx)
  end

  test "extracts a typed Farcaster account", ctx do
    linked_accounts =
      Jason.encode!([
        %{
          "type" => "farcaster",
          "fid" => 12_345,
          "username" => "regent"
        }
      ])

    token =
      base_claims()
      |> Map.put("linked_accounts", linked_accounts)
      |> sign(ctx.private_pem)

    assert {:ok,
            %{
              linked_socials: [
                %{
                  provider: :farcaster,
                  subject: "12345",
                  username: "regent",
                  display_name: nil
                }
              ]
            }} = verify(token, ctx)
  end

  test "returns wallet and social accounts from the same token", ctx do
    linked_accounts =
      Jason.encode!([
        %{
          "type" => "wallet",
          "address" => "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          "lv" => 1_700_000_000
        },
        %{
          "type" => "github_oauth",
          "subject" => "github-user-7",
          "username" => "regents-ai"
        }
      ])

    token =
      base_claims()
      |> Map.put("linked_accounts", linked_accounts)
      |> sign(ctx.private_pem)

    assert {:ok,
            %{
              wallet_address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
              wallet_addresses: ["0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"],
              linked_socials: [
                %{
                  provider: :github,
                  subject: "github-user-7",
                  username: "regents-ai",
                  display_name: nil
                }
              ]
            }} = verify(token, ctx)
  end

  test "skips malformed and unsupported social accounts", ctx do
    linked_accounts =
      Jason.encode!([
        %{"type" => "twitter_oauth", "username" => "missing-subject"},
        %{"type" => "github_oauth", "subject" => 7, "username" => "wrong-subject-type"},
        %{"type" => "farcaster", "fid" => "123", "username" => "wrong-fid-type"},
        %{"type" => "twitter_oauth", "subject" => "x-1", "username" => 123},
        %{"type" => "email", "subject" => "ignored"},
        %{"type" => "github_oauth", "subject" => "github-user-8"}
      ])

    token =
      base_claims()
      |> Map.put("linked_accounts", linked_accounts)
      |> sign(ctx.private_pem)

    assert {:ok,
            %{
              linked_socials: [
                %{
                  provider: :github,
                  subject: "github-user-8",
                  username: nil,
                  display_name: nil
                }
              ]
            }} = verify(token, ctx)
  end

  test "returns an empty social list when linked_accounts is absent", ctx do
    token = sign(base_claims(), ctx.private_pem)

    assert {:ok,
            %{
              wallet_address: nil,
              wallet_addresses: [],
              linked_socials: []
            } = verified} = verify(token, ctx)

    refute Map.has_key?(verified, :__struct__)
  end

  test "only Ethereum wallet accounts provide wallet evidence", ctx do
    address = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"

    for account <- [
          %{"type" => "email", "address" => address},
          %{"address" => address},
          %{"type" => "wallet", "chain_type" => "solana", "address" => address, "lv" => 1}
        ] do
      token =
        base_claims()
        |> Map.put("linked_accounts", Jason.encode!([account]))
        |> sign(ctx.private_pem)

      assert {:ok, %{wallet_addresses: [], wallet_address: nil}} = verify(token, ctx)
    end
  end

  test "a present non-string linked_accounts claim is malformed", ctx do
    for invalid <- [nil, [], %{}, 42] do
      token = base_claims() |> Map.put("linked_accounts", invalid) |> sign(ctx.private_pem)
      assert {:error, :invalid_linked_accounts} = verify(token, ctx)
    end
  end

  test "paired proof keeps signed X identity without requiring a wallet", ctx do
    identity =
      Map.put(
        base_claims(),
        "linked_accounts",
        Jason.encode!([
          %{"type" => "twitter_oauth", "subject" => "x-42", "username" => "changed_handle"}
        ])
      )

    access = Map.put(base_claims(), "sid", "session-1")

    assert {:ok,
            %RegentPrivy.Session{
              app_id: @app_id,
              session_id: "session-1",
              wallet_addresses: [],
              linked_socials: [%{subject: "x-42", username: "changed_handle"}],
              expires_at: expires
            }} = verify_pair(access, identity, ctx)

    assert expires == @now + 3600
    assert {:ok, _} = verify_pair(access, Map.put(identity, "sid", "session-1"), ctx)
  end

  test "pair binding rejects substitution and confused roles", ctx do
    access = Map.put(base_claims(), "sid", "session-1")
    identity = Map.put(base_claims(), "linked_accounts", "[]")

    assert {:error, {:pair_binding, :subject_mismatch}} =
             verify_pair(access, Map.put(identity, "sub", "other-person"), ctx)

    assert {:error, {:pair_binding, :session_mismatch}} =
             verify_pair(access, Map.put(identity, "sid", "other-session"), ctx)

    assert {:error, {:pair_binding, :session_mismatch}} =
             verify_pair(access, Map.put(identity, "sid", nil), ctx)

    assert {:error, {:access_verification, :missing_session_id}} =
             verify_pair(Map.delete(access, "sid"), identity, ctx)

    assert {:error, {:pair_binding, :access_role_confused}} =
             verify_pair(Map.put(access, "linked_accounts", "[]"), identity, ctx)

    assert {:error, {:pair_binding, :identity_accounts_missing}} =
             verify_pair(access, Map.delete(identity, "linked_accounts"), ctx)

    assert {:error, {:identity_verification, :invalid_audience}} =
             verify_pair(access, Map.put(identity, "aud", "other-app"), ctx)

    assert {:error, {:identity_verification, :token_expired}} =
             verify_pair(access, Map.put(identity, "exp", @now), ctx)

    assert {:error, {:access_verification, :token_expired}} =
             verify_pair(Map.put(access, "exp", @now), identity, ctx)

    assert {:error, {:configuration, :missing_privy_config}} =
             RegentPrivy.Session.verify(%{access: "unused", identity: "unused"}, [])
  end

  test "a configured rotation set verifies either signer and cross-key pairs", ctx do
    other = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, private} = JOSE.JWK.to_pem(other)
    {_, public} = other |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    opts = [app_id: @app_id, verification_keys: [ctx.public_pem, public], now: @now]

    for signing_key <- [ctx.private_pem, private] do
      assert {:ok, _} = RegentPrivy.verify_token(sign(base_claims(), signing_key), opts)
    end

    pair = %{
      access: sign(Map.put(base_claims(), "sid", "session-1"), ctx.private_pem),
      identity: sign(Map.put(base_claims(), "linked_accounts", "[]"), private)
    }

    assert {:ok, %RegentPrivy.Session{session_id: "session-1"}} =
             RegentPrivy.Session.verify(pair, opts)

    bad_identity =
      sign(base_claims() |> Map.put("linked_accounts", "[]") |> Map.put("sub", "other"), private)

    assert {:error, {:pair_binding, :subject_mismatch}} =
             RegentPrivy.Session.verify(%{pair | identity: bad_identity}, opts)

    expired = sign(Map.put(base_claims(), "exp", @now), private)
    assert {:error, :token_expired} = RegentPrivy.verify_token(expired, opts)
    wrong_app = sign(Map.put(base_claims(), "aud", "other-app"), private)
    assert {:error, :invalid_audience} = RegentPrivy.verify_token(wrong_app, opts)
  end

  test "an explicit malformed rotation set cannot fall back to a valid singular key", ctx do
    token = sign(base_claims(), ctx.private_pem)

    for keys <- [
          [],
          nil,
          "not-a-list",
          [nil],
          [ctx.public_pem, ""],
          List.duplicate(ctx.public_pem, 5)
        ] do
      assert {:error, :invalid_verification_key} = verify(token, ctx, verification_keys: keys)
    end

    assert {:error, :token_verification_failed} =
             RegentPrivy.verify_token(token,
               app_id: @app_id,
               verification_keys: ["not a pem"],
               now: @now
             )
  end

  defp verify_pair(access, identity, ctx) do
    RegentPrivy.Session.verify(
      %{access: sign(access, ctx.private_pem), identity: sign(identity, ctx.private_pem)},
      app_id: @app_id,
      verification_key: ctx.public_pem,
      now: @now
    )
  end
end

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

  test "extracts normalized wallet addresses from linked_accounts", ctx do
    linked_accounts =
      Jason.encode!([
        %{"type" => "wallet", "address" => " 0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266 "},
        %{"type" => "wallet", "address" => "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"},
        %{"type" => "email", "value" => "a@b.c"},
        %{"type" => "wallet", "address" => "not-a-wallet"}
      ])

    token =
      base_claims()
      |> Map.put("linked_accounts", linked_accounts)
      |> sign(ctx.private_pem)

    assert {:ok,
            %{
              wallet_address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
              wallet_addresses: ["0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"]
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
          "username" => "regents-ai",
          "name" => "Regents"
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
                  display_name: "Regents"
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
          "username" => "regent",
          "display_name" => "Regent FC"
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
                  display_name: "Regent FC"
                }
              ]
            }} = verify(token, ctx)
  end

  test "returns wallet and social accounts from the same token", ctx do
    linked_accounts =
      Jason.encode!([
        %{"type" => "wallet", "address" => "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"},
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

    assert {:ok, %RegentPrivy.VerifiedPrivyIdentity{linked_socials: []}} = verify(token, ctx)
  end
end

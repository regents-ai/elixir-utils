defmodule RegentChatGPT.OAuthTest do
  use ExUnit.Case, async: true

  import RegentChatGPT.TestSupport

  alias RegentChatGPT.{Config, Error, OAuth, TokenSet}

  test "builds the loopback authorization URL" do
    url =
      OAuth.authorization_url(Config.resolve(),
        redirect_uri: "http://localhost:1455/auth/callback",
        pkce: %{challenge: "challenge"},
        state: "state"
      )

    parsed = URI.parse(url)
    query = URI.decode_query(parsed.query)

    assert "#{parsed.scheme}://#{parsed.host}#{parsed.path}" ==
             "https://auth.openai.com/oauth/authorize"

    assert query["response_type"] == "code"
    assert query["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann"
    assert query["code_challenge"] == "challenge"
    assert query["code_challenge_method"] == "S256"
    assert query["originator"] == "codex_cli_rs"
  end

  test "exchanges an authorization code for normalized tokens" do
    id_token =
      jwt(%{
        "https://api.openai.com/auth" => %{"chatgpt_account_id" => "acct_123"}
      })

    parent = self()

    config =
      Config.resolve(
        http_client: fn request ->
          send(parent, {:request, request})

          {:ok,
           %{
             status: 200,
             body: %{
               "access_token" => "access.jwt.token",
               "refresh_token" => "refresh",
               "id_token" => id_token,
               "expires_in" => 3600
             }
           }}
        end
      )

    assert {:ok, %TokenSet{} = tokens} =
             OAuth.exchange_authorization_code(config,
               code: "code",
               code_verifier: "verifier",
               redirect_uri: "http://localhost/callback"
             )

    assert tokens.refresh_token == "refresh"
    assert tokens.id_token == id_token
    assert tokens.account_id == "acct_123"
    assert is_integer(tokens.expires_at)

    assert_receive {:request, request}
    assert request[:method] == :post
    assert request[:url] == "https://auth.openai.com/oauth/token"
    assert URI.decode_query(request[:body])["grant_type"] == "authorization_code"
  end

  test "refresh keeps the previous refresh token when OpenAI does not rotate it" do
    config =
      Config.resolve(
        http_client: fn _request ->
          {:ok, %{status: 200, body: %{"access_token" => "new.access.token", "expires_in" => 10}}}
        end
      )

    assert {:ok, %TokenSet{access_token: "new.access.token", refresh_token: "old_refresh"}} =
             OAuth.refresh_tokens(config, "old_refresh")
  end

  test "classifies dead refresh tokens as reconnect-required" do
    config =
      Config.resolve(
        http_client: fn _request ->
          {:ok, %{status: 400, body: Jason.encode!(%{"error" => "invalid_grant"})}}
        end
      )

    assert {:error, %Error{code: :refresh_token_invalid, status: 400}} =
             OAuth.refresh_tokens(config, "dead_refresh")
  end

  test "rejects token responses without an access token" do
    config = Config.resolve(http_client: fn _request -> {:ok, %{status: 200, body: %{}}} end)

    assert {:error, %Error{code: :token_exchange_failed}} =
             OAuth.exchange_authorization_code(config,
               code: "code",
               code_verifier: "verifier",
               redirect_uri: "http://localhost/callback"
             )
  end
end

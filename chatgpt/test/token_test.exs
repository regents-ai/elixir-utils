defmodule RegentChatGPT.TokenTest do
  use ExUnit.Case, async: true

  import RegentChatGPT.TestSupport

  alias RegentChatGPT.{Config, Error, Token, TokenSet}

  test "returns current tokens when the access token is still fresh" do
    id_token = jwt(%{"https://api.openai.com/auth" => %{"chatgpt_account_id" => "acct_123"}})

    tokens = %TokenSet{
      access_token: "access",
      id_token: id_token,
      expires_at: 100_000
    }

    assert {:ok, %TokenSet{account_id: "acct_123"}} =
             Token.ensure_fresh_tokens(Config.resolve(), tokens, now: fn -> 1_000 end)
  end

  test "refreshes expired tokens and calls on_refresh" do
    parent = self()

    config =
      Config.resolve(
        http_client: fn _request ->
          {:ok,
           %{
             status: 200,
             body: %{"access_token" => "fresh", "refresh_token" => "rotated", "expires_in" => 20}
           }}
        end
      )

    expired = %TokenSet{access_token: "old", refresh_token: "refresh", expires_at: 1_000}

    assert {:ok, %TokenSet{access_token: "fresh", refresh_token: "rotated"}} =
             Token.ensure_fresh_tokens(config, expired,
               now: fn -> 2_000 end,
               on_refresh: fn tokens -> send(parent, {:refreshed, tokens}) end
             )

    assert_receive {:refreshed, %TokenSet{access_token: "fresh"}}
  end

  test "does not silently use expired access tokens without refresh" do
    expired = %TokenSet{access_token: "old", expires_at: 1_000}

    assert {:error, %Error{code: :not_authenticated}} =
             Token.ensure_fresh_tokens(Config.resolve(), expired, now: fn -> 2_000 end)
  end
end

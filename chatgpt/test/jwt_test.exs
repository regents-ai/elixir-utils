defmodule RegentChatGPT.JWTTest do
  use ExUnit.Case, async: true

  import RegentChatGPT.TestSupport

  alias RegentChatGPT.JWT

  test "parses account, plan, and expiry claims from an OpenAI-issued token" do
    token =
      jwt(%{
        "email" => "founder@example.com",
        "name" => "Founder",
        "exp" => 1_800_000_000,
        "https://api.openai.com/auth" => %{
          "chatgpt_account_id" => "acct_123",
          "chatgpt_plan_type" => "pro"
        }
      })

    assert JWT.derive_account_id(token) == "acct_123"
    assert JWT.token_expiry(token) == 1_800_000_000_000

    assert %RegentChatGPT.User{
             account_id: "acct_123",
             email: "founder@example.com",
             name: "Founder",
             plan: "pro"
           } = JWT.parse_user(token)
  end

  test "returns nil for malformed tokens" do
    refute JWT.decode_claims("not-a-token")
    refute JWT.derive_account_id(nil)
    refute JWT.parse_user("a.b.c")
  end
end

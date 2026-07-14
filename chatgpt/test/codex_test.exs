defmodule RegentChatGPT.CodexTest do
  use ExUnit.Case, async: true

  alias RegentChatGPT.{Codex, Config, Error, TokenSet}

  test "normalizes responses bodies for the ChatGPT-backed Codex endpoint" do
    body =
      Codex.normalize_responses_body(%{
        "model" => "gpt-5.5",
        "input" => [
          %{"id" => "item_1", "role" => "user", "content" => "Hello"},
          %{"type" => "item_reference", "id" => "old"}
        ],
        "include" => ["file_search_call.results"],
        "max_output_tokens" => 100,
        "reasoning" => %{"effort" => "high"}
      })

    assert body["store"] == false
    assert body["reasoning"] == %{"effort" => "high", "summary" => "auto"}
    assert body["text"] == %{"verbosity" => "medium"}
    assert "reasoning.encrypted_content" in body["include"]
    assert [%{"role" => "user", "content" => "Hello"}] = body["input"]
    refute Map.has_key?(body, "max_output_tokens")
  end

  test "builds a responses request with Codex headers and client version" do
    config = Config.resolve()
    tokens = %TokenSet{access_token: "access", account_id: "acct_123"}

    assert {:ok, request} =
             Codex.responses_request(config, tokens, %{
               "input" => [%{"role" => "user", "content" => "Hello"}]
             })

    assert request[:method] == :post

    assert request[:url] ==
             "https://chatgpt.com/backend-api/codex/responses?client_version=0.142.5"

    assert {"authorization", "Bearer access"} in request[:headers]
    assert {"chatgpt-account-id", "acct_123"} in request[:headers]

    body = Jason.decode!(request[:body])
    assert body["model"] == "gpt-5.5"
    assert body["store"] == false
  end

  test "resolves OpenAI-style URLs onto the Codex base URL" do
    assert Codex.resolve_target_url(
             "https://api.openai.com/v1/responses?stream=true",
             "https://chatgpt.com/backend-api/codex"
           ) ==
             "https://chatgpt.com/backend-api/codex/responses?stream=true"

    assert Codex.resolve_target_url(
             "/backend-api/codex/models",
             "https://chatgpt.com/backend-api/codex"
           ) ==
             "https://chatgpt.com/backend-api/codex/models"
  end

  test "extracts unique model slugs from known list shapes" do
    assert Codex.extract_model_slugs(%{
             "models" => [
               %{"slug" => "gpt-5.5"},
               %{"id" => "gpt-5.4"},
               %{"name" => "gpt-5.5"},
               "o3"
             ]
           }) == ["gpt-5.5", "gpt-5.4", "o3"]
  end

  test "lists models through injected HTTP" do
    parent = self()

    config =
      Config.resolve(
        http_client: fn request ->
          send(parent, {:request, request})
          {:ok, %{status: 200, body: %{"models" => [%{"slug" => "gpt-5.5"}]}}}
        end
      )

    tokens = %TokenSet{access_token: "access", account_id: "acct_123"}

    assert {:ok, ["gpt-5.5"]} = Codex.list_models(config, tokens)

    assert_receive {:request, request}
    assert request[:url] == "https://chatgpt.com/backend-api/codex/models?client_version=0.142.5"
    assert {"originator", "codex_cli_rs"} in request[:headers]
  end

  test "requires account authorization for Codex requests" do
    assert {:error, %Error{code: :not_authenticated}} =
             Codex.responses_request(Config.resolve(), %TokenSet{access_token: "access"}, %{})
  end
end

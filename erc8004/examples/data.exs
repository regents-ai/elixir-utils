defmodule RegentERC8004.ExampleData do
  @moduledoc "Synthetic display examples only. No real agent, feedback or validation claims."
  def registry, do: "eip155:8453:0x1111111111111111111111111111111111111111"

  def data do
    %{
      "protocol" => %{
        "chainId" => "8453",
        "identityRegistry" => "0x1111111111111111111111111111111111111111"
      },
      "agent" => %{
        "chainId" => "8453",
        "agentId" => "7",
        "owner" => "0x2222222222222222222222222222222222222222",
        "lastActivity" => "1700000000",
        "registrationFile" => %{
          "name" => "Example agent (synthetic)",
          "description" =>
            "A small, server-rendered agent identity. This is demonstration data, not a real registration or a claim about a live agent.",
          "mcpEndpoint" => "https://example.org/mcp",
          "a2aEndpoint" => nil,
          "oasfEndpoint" => nil,
          "webEndpoint" => "https://example.org",
          "emailEndpoint" => "example@example.org"
        }
      },
      "reputation" => [
        %{"feedbackCreated" => "4", "feedbackRevoked" => "1", "valueDeltaSum" => "14.25"}
      ],
      "validation" => [%{"validationResponses" => "1", "scoreSum" => "0"}],
      "feedbacks" =>
        Enum.with_index(["12.5", "-1.25", "3"], fn value, i ->
          %{
            "id" => "synthetic-feedback-#{i}",
            "clientAddress" => "0x3333333333333333333333333333333333333333",
            "value" => value,
            "tag1" => "example",
            "tag2" => "unscaled",
            "isRevoked" => false,
            "createdAt" => Integer.to_string(1_700_000_000 - i),
            "feedbackFile" => %{
              "text" =>
                "Synthetic feedback entry #{i}. Signed values are preserved; they are not percentages."
            }
          }
        end),
      "validations" =>
        Enum.with_index([{"PENDING", nil}, {"COMPLETED", 0}, {"EXPIRED", nil}], fn {status, score},
                                                                                   i ->
          %{
            "id" => "synthetic-validation-#{i}",
            "validatorAddress" => "0x4444444444444444444444444444444444444444",
            "response" => score,
            "status" => status,
            "tag" => "example only",
            "createdAt" => Integer.to_string(1_700_000_000 - i)
          }
        end)
    }
  end
end

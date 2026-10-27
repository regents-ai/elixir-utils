defmodule RegentAnthropicTest do
  use ExUnit.Case, async: false

  alias RegentAnthropic.{Error, Reply}

  @api_key "test-anthropic-key-never-shown"

  setup do
    previous_client = Application.get_env(:regent_http, :client)
    previous_key = Application.get_env(:regent_anthropic, :api_key)

    Application.put_env(:regent_http, :client, __MODULE__.Client)
    Application.put_env(:regent_anthropic, :api_key, @api_key)
    Process.put(:test_pid, self())

    on_exit(fn ->
      restore(:regent_http, :client, previous_client)
      restore(:regent_anthropic, :api_key, previous_key)
    end)
  end

  describe "respond/1" do
    test "prices fresh input, cache writes, cache reads and output at their own prices" do
      answer(200, %{
        "id" => "msg_1",
        "content" => [
          %{"type" => "thinking", "thinking" => "", "signature" => "sig"},
          %{"type" => "text", "text" => ~s({"plan":"swap"})}
        ],
        "stop_reason" => "end_turn",
        "usage" => %{
          "input_tokens" => 1000,
          "cache_creation_input_tokens" => 200,
          "cache_read_input_tokens" => 400,
          "output_tokens" => 500
        }
      })

      assert {:ok, %Reply{} = reply} =
               RegentAnthropic.respond(
                 model: "claude-opus-5-5",
                 system: "Plan it.",
                 input: [{:text, "Look"}, {:image, "image/png", "PNG"}],
                 schema: %{"type" => "object"},
                 effort: "high",
                 max_tokens: 32_000
               )

      # 1000 × $4.00 + 200 × $5.00 + 400 × $0.20 + 500 × $20.00, per million tokens
      assert Decimal.equal?(reply.cost_usd, Decimal.new("0.01508"))
      assert reply.json == %{"plan" => "swap"}

      assert reply.usage == %{
               input_tokens: 1000,
               cache_write_tokens: 200,
               cache_read_tokens: 400,
               output_tokens: 500
             }

      assert_received {:request, opts}
      assert opts[:url] == "https://api.anthropic.com/v1/messages"
      assert opts[:retry] == false
      assert {"anthropic-version", "2023-06-01"} in opts[:headers]
      assert opts[:json].thinking == %{type: "adaptive"}
      assert opts[:json].output_config.effort == "high"
      assert opts[:json].output_config.format.type == "json_schema"
    end

    test "a reply that stopped early still reports what it cost" do
      answer(200, %{
        "id" => "msg_2",
        "content" => [],
        "stop_reason" => "max_tokens",
        "usage" => %{"input_tokens" => 100, "output_tokens" => 2000}
      })

      assert {:error, %Error{reason: {:incomplete, "max_tokens"}, cost_usd: cost}} =
               RegentAnthropic.respond(
                 model: "claude-opus-5-5",
                 system: "Hi",
                 input: "Hi",
                 max_tokens: 2000
               )

      assert Decimal.equal?(cost, Decimal.new("0.0404"))
    end

    test "a refused reply is an error that still reports what it cost" do
      answer(200, %{
        "id" => "msg_3",
        "content" => [],
        "stop_reason" => "refusal",
        "usage" => %{"input_tokens" => 500, "output_tokens" => 50}
      })

      assert {:error, %Error{reason: :refused, cost_usd: cost}} =
               RegentAnthropic.respond(
                 model: "claude-opus-5-5",
                 system: "Hi",
                 input: "Hi",
                 max_tokens: 100
               )

      # 500 × $4.00 + 50 × $20.00, per million tokens
      assert Decimal.equal?(cost, Decimal.new("0.003"))
    end

    test "a model without a price is refused before anything is sent" do
      assert {:error, %Error{reason: {:unpriced_model, "claude-9"}, cost_usd: nil}} =
               RegentAnthropic.respond(
                 model: "claude-9",
                 system: "Hi",
                 input: "Hi",
                 max_tokens: 10
               )

      refute_received {:request, _opts}
    end

    test "an Anthropic error names its status, type and message and never the key" do
      answer(429, %{
        "type" => "error",
        "error" => %{"type" => "rate_limit_error", "message" => "Slow down"}
      })

      assert {:error, %Error{reason: {:anthropic, 429, "rate_limit_error", "Slow down"}} = error} =
               RegentAnthropic.respond(
                 model: "claude-opus-5-5",
                 system: "Hi",
                 input: "Hi",
                 max_tokens: 10
               )

      assert Exception.message(error) == "Anthropic answered 429 (rate_limit_error): Slow down"
      refute inspect(error) =~ @api_key
      refute Exception.message(error) =~ @api_key
    end
  end

  defp answer(status, body), do: Process.put(:answer, %Req.Response{status: status, body: body})

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)

  defmodule Client do
    @behaviour RegentHttp

    @impl true
    def request(opts) do
      send(Process.get(:test_pid), {:request, opts})
      {:ok, Process.get(:answer)}
    end
  end
end

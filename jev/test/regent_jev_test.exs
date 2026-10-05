defmodule RegentJevTest do
  use ExUnit.Case, async: false

  alias RegentJev.{Decision, Error}

  @api_key "test-openrouter-key-never-shown"

  @questions %{
    "label" => %{
      instructions: "Which label fits this note?",
      choices: %{"idea" => "Something to try.", "task" => "Something to do."}
    }
  }

  setup do
    previous_client = Application.get_env(:regent_http, :client)
    previous_key = Application.get_env(:regent_jev, :api_key)

    Application.put_env(:regent_http, :client, __MODULE__.Client)
    Application.put_env(:regent_jev, :api_key, @api_key)
    Process.put(:test_pid, self())

    test_pid = self()
    handler = "regent-jev-test-#{inspect(test_pid)}"

    :telemetry.attach(handler, [:regent_jev, :decide], &__MODULE__.forward/4, test_pid)

    on_exit(fn ->
      :telemetry.detach(handler)
      restore(:regent_http, :client, previous_client)
      restore(:regent_jev, :api_key, previous_key)
    end)
  end

  test "an offered choice comes back with its confidence, tokens and cost" do
    answer(200, %{
      "model" => "typesafe/jev-1.13-20260917",
      "answers" => %{
        "label" => %{
          "type" => "choice",
          "choice" => "task",
          "confidence" => 0.75,
          "probabilities" => %{"idea" => 0.16, "task" => 0.84}
        }
      },
      "usage" => %{"input_tokens" => 476, "output_tokens" => 70, "cost" => 0.000019992}
    })

    assert {:ok, %Decision{} = decision} =
             RegentJev.decide(%{title: "Buy milk"}, @questions, model: "~typesafe/jev-latest")

    assert decision.answers == %{"label" => %{choice: "task", confidence: 0.75}}
    assert decision.model == "typesafe/jev-1.13-20260917"
    assert decision.usage == %{input_tokens: 476, output_tokens: 70}
    assert Decimal.equal?(decision.cost_usd, Decimal.new("0.000019992"))

    assert_received {:request, opts}
    assert opts[:url] == "https://openrouter.ai/api/alpha/decisions"
    assert opts[:auth] == {:bearer, @api_key}
    assert opts[:retry] == false

    assert opts[:json] == %{
             model: "~typesafe/jev-latest",
             state: %{title: "Buy milk"},
             questions: %{
               "label" => %{
                 type: "choice",
                 instructions: "Which label fits this note?",
                 criteria: %{"idea" => "Something to try.", "task" => "Something to do."}
               }
             }
           }

    assert_received {:telemetry, %{input_tokens: 476, output_tokens: 70, cost_usd: 1.9992e-5},
                     %{model: "~typesafe/jev-latest", outcome: :ok}}
  end

  test "a choice that was not offered is refused but still reports its cost" do
    answer(200, %{
      "model" => "typesafe/jev-1.13-20260917",
      "answers" => %{"label" => %{"type" => "choice", "choice" => "recipe"}},
      "usage" => %{"input_tokens" => 400, "output_tokens" => 10, "cost" => 0.0000168}
    })

    assert {:error, %Error{reason: {:unexpected_answer, "label"}} = error} =
             RegentJev.decide("note", @questions, model: "~typesafe/jev-latest")

    assert error.usage == %{input_tokens: 400, output_tokens: 10}
    assert Decimal.equal?(error.cost_usd, Decimal.new("0.0000168"))
    assert_received {:telemetry, %{cost_usd: 1.68e-5}, %{outcome: :unexpected_answer}}
  end

  test "an OpenRouter error names its status and costs nothing" do
    answer(429, %{"error" => %{"code" => 429, "message" => "Rate limited"}})

    assert {:error, %Error{reason: {:openrouter, 429, 429}, usage: nil, cost_usd: nil}} =
             RegentJev.decide("note", @questions, model: "~typesafe/jev-latest")

    assert_received {:telemetry, %{cost_usd: +0.0, input_tokens: 0}, %{outcome: :http_error}}
  end

  test "without a key nothing is sent" do
    Application.delete_env(:regent_jev, :api_key)

    assert {:error, %Error{reason: :api_key_missing}} =
             RegentJev.decide("note", @questions, model: "~typesafe/jev-latest")

    refute_received {:request, _opts}
  end

  def forward(_event, measurements, metadata, test_pid),
    do: send(test_pid, {:telemetry, measurements, metadata})

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

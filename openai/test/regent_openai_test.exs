defmodule RegentOpenAITest do
  use ExUnit.Case, async: false

  alias RegentOpenAI.{Error, Reply, Speech, Transcript}

  @api_key "test-openai-key-never-shown"

  setup do
    previous_client = Application.get_env(:regent_http, :client)
    previous_key = Application.get_env(:regent_openai, :api_key)

    Application.put_env(:regent_http, :client, __MODULE__.Client)
    Application.put_env(:regent_openai, :api_key, @api_key)
    Process.put(:test_pid, self())

    on_exit(fn ->
      restore(:regent_http, :client, previous_client)
      restore(:regent_openai, :api_key, previous_key)
    end)
  end

  describe "respond/1" do
    test "cost splits cached input from fresh input at their own prices" do
      answer(200, %{
        "id" => "resp_1",
        "status" => "completed",
        "output" => [
          %{"type" => "reasoning", "summary" => []},
          %{
            "type" => "message",
            "content" => [%{"type" => "output_text", "text" => ~s({"plan":"swap"})}]
          }
        ],
        "usage" => %{
          "input_tokens" => 1000,
          "input_tokens_details" => %{"cached_tokens" => 400},
          "output_tokens" => 500
        }
      })

      assert {:ok, %Reply{} = reply} =
               RegentOpenAI.respond(
                 model: "gpt-5.6-terra",
                 instructions: "Plan it.",
                 input: [{:text, "Look"}, {:image_url, "data:image/png;base64,AA=="}],
                 schema: {"plan", %{"type" => "object"}},
                 reasoning: "low"
               )

      # 600 × $2.00 + 400 × $0.20 + 500 × $12.00, per million tokens
      assert Decimal.equal?(reply.cost_usd, Decimal.new("0.00728"))
      assert reply.json == %{"plan" => "swap"}
      assert reply.usage == %{input_tokens: 1000, cached_input_tokens: 400, output_tokens: 500}

      assert_received {:request, opts}
      assert opts[:url] == "https://api.openai.com/v1/responses"
      assert opts[:retry] == false
      assert opts[:json].store == false
      assert opts[:json].text.format.strict == true
    end

    test "a reply that stopped early still reports what it cost" do
      answer(200, %{
        "id" => "resp_2",
        "status" => "incomplete",
        "incomplete_details" => %{"reason" => "max_output_tokens"},
        "output" => [],
        "usage" => %{
          "input_tokens" => 100,
          "input_tokens_details" => %{"cached_tokens" => 0},
          "output_tokens" => 2000
        }
      })

      assert {:error, %Error{reason: {:incomplete, "max_output_tokens"}, cost_usd: cost}} =
               RegentOpenAI.respond(model: "gpt-5.6-luna", instructions: "Hi", input: "Hi")

      assert Decimal.equal?(cost, Decimal.new("0.00242"))
    end

    test "a model without a price is refused before anything is sent" do
      assert {:error, %Error{reason: {:unpriced_model, "gpt-9"}, cost_usd: nil}} =
               RegentOpenAI.respond(model: "gpt-9", instructions: "Hi", input: "Hi")

      refute_received {:request, _opts}
    end

    test "an OpenAI error names its status and code and never the key" do
      answer(429, %{"error" => %{"code" => "rate_limit_exceeded", "message" => "Slow down"}})

      assert {:error, %Error{reason: {:openai, 429, "rate_limit_exceeded"}} = error} =
               RegentOpenAI.respond(model: "gpt-5.6-luna", instructions: "Hi", input: "Hi")

      refute inspect(error) =~ @api_key
      refute Exception.message(error) =~ @api_key
    end
  end

  describe "transcribe/2" do
    test "sends the audio as a file and prices the tokens it reports" do
      answer(200, %{
        "text" => "stake ten regent",
        "usage" => %{
          "type" => "tokens",
          "input_tokens" => 400,
          "input_token_details" => %{"audio_tokens" => 390, "text_tokens" => 10},
          "output_tokens" => 20,
          "total_tokens" => 420
        }
      })

      assert {:ok, %Transcript{text: "stake ten regent", cost_usd: cost}} =
               RegentOpenAI.transcribe("AUDIO",
                 model: "gpt-4o-mini-transcribe",
                 filename: "clip.webm",
                 content_type: "audio/webm",
                 language: "en"
               )

      # 400 × $1.25 + 20 × $5.00, per million tokens
      assert Decimal.equal?(cost, Decimal.new("0.0006"))

      assert_received {:request, opts}

      assert opts[:form_multipart] == [
               file: {"AUDIO", filename: "clip.webm", content_type: "audio/webm", size: 5},
               model: "gpt-4o-mini-transcribe",
               language: "en"
             ]
    end

    test "audio over 25 MB is refused before anything is sent" do
      audio = :binary.copy("a", 25 * 1024 * 1024 + 1)

      assert {:error, %Error{reason: {:audio_too_large, 26_214_401}}} =
               RegentOpenAI.transcribe(audio,
                 model: "gpt-4o-mini-transcribe",
                 filename: "clip.webm",
                 content_type: "audio/webm"
               )

      refute_received {:request, _opts}
    end
  end

  describe "speak/2" do
    test "joins the streamed audio and prices the closing usage" do
      events =
        [
          %{"type" => "speech.audio.delta", "audio" => Base.encode64("ID3")},
          %{"type" => "speech.audio.delta", "audio" => Base.encode64("-frames")},
          %{
            "type" => "speech.audio.done",
            "usage" => %{"input_tokens" => 14, "output_tokens" => 101, "total_tokens" => 115}
          }
        ]
        |> Enum.map_join(fn event -> "data: " <> Jason.encode!(event) <> "\n\n" end)

      answer(200, events)

      assert {:ok, %Speech{audio: "ID3-frames", content_type: "audio/mpeg", cost_usd: cost}} =
               RegentOpenAI.speak("Done.", model: "gpt-4o-mini-tts", voice: "marin")

      # 14 × $0.60 + 101 × $12.00, per million tokens
      assert Decimal.equal?(cost, Decimal.new("0.0012204"))

      assert_received {:request, opts}
      assert opts[:json].stream_format == "sse"
    end

    test "text over 4,096 characters is refused before anything is sent" do
      assert {:error, %Error{reason: {:text_too_long, 4097}}} =
               RegentOpenAI.speak(String.duplicate("a", 4097),
                 model: "gpt-4o-mini-tts",
                 voice: "marin"
               )

      refute_received {:request, _opts}
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

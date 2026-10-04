defmodule RegentJev do
  @moduledoc """
  Typed questions to Jev, TypeSafe's decision model on OpenRouter, for Regent
  Elixir apps.

  Jev is not a chat model. It answers named questions about a `state` through
  OpenRouter's Decisions endpoint, each by picking one of the keys it was
  offered, with a confidence. `decide/3` returns the answers only when every
  question came back with one of its own keys, and every result carries the
  tokens it used and their cost in US dollars as OpenRouter reported it.
  Nothing is retried; the caller's job queue retries.

  The app sets the key in `config/runtime.exs`, and may point the package at a
  local stand-in while developing:

      config :regent_jev, api_key: System.fetch_env!("OPENROUTER_API_KEY")
      config :regent_jev, endpoint: "http://127.0.0.1:4198/api/alpha/decisions"

  Requests go through `RegentHttp`, so tests stub the client there. Each call
  emits a `[:regent_jev, :decide]` telemetry event (see `decide/3`).
  """

  alias RegentJev.{Decision, Error}

  @endpoint "https://openrouter.ai/api/alpha/decisions"
  @receive_timeout 30_000

  @type usage :: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()}

  @type question :: %{instructions: String.t(), choices: %{String.t() => String.t()}}

  @doc """
  Asks Jev every question in `questions` about `state`, in one call.

  `questions` maps a name to `%{instructions: text, choices: %{key => meaning}}`.
  `state` is any JSON value and must hold only what may leave the site.

  Options:

    * `:model` (required) — such as `"~typesafe/jev-latest"`
    * `:receive_timeout` — milliseconds to wait, 30,000 by default

  Emits `[:regent_jev, :decide]` with measurements `duration` (native time),
  `input_tokens`, `output_tokens` and `cost_usd` (a float; 0 when nothing was
  billed) and metadata `model` and `outcome`: `:ok`, `:api_key_missing`,
  `:http_error`, `:transport`, `:unexpected_answer` or `:unexpected_response`.
  """
  @spec decide(term(), %{String.t() => question()}, keyword()) ::
          {:ok, Decision.t()} | {:error, Error.t()}
  def decide(state, questions, opts) when map_size(questions) > 0 do
    model = Keyword.fetch!(opts, :model)
    started_at = System.monotonic_time()

    result =
      with {:ok, api_key} <- api_key(),
           {:ok, body} <- post(api_key, request(model, state, questions), opts) do
        answers(body, questions)
      end

    emit(result, model, System.monotonic_time() - started_at)
    result
  end

  defp request(model, state, questions) do
    %{
      model: model,
      state: state,
      questions:
        Map.new(questions, fn {name, %{instructions: instructions, choices: choices}} ->
          {name, %{type: "choice", instructions: instructions, criteria: choices}}
        end)
    }
  end

  defp api_key do
    case Application.get_env(:regent_jev, :api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, %Error{reason: :api_key_missing}}
    end
  end

  defp post(api_key, body, opts) do
    Application.get_env(:regent_jev, :endpoint, @endpoint)
    |> RegentHttp.post(
      auth: {:bearer, api_key},
      json: body,
      retry: false,
      receive_timeout: Keyword.get(opts, :receive_timeout, @receive_timeout)
    )
    |> handle_response()
  end

  defp handle_response({:ok, %{status: 200, body: body}}) when is_map(body), do: {:ok, body}
  defp handle_response({:ok, %{status: 200}}), do: {:error, %Error{reason: :unexpected_response}}

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, %Error{reason: {:openrouter, status, error_code(body)}}}
  end

  defp handle_response({:error, reason}) do
    {:error, %Error{reason: {:transport, RegentHttp.format_error(reason)}}}
  end

  defp error_code(%{"error" => %{"code" => code}}) when is_binary(code) or is_integer(code),
    do: code

  defp error_code(_body), do: nil

  defp answers(
         %{
           "model" => model,
           "answers" => answers,
           "usage" => %{"input_tokens" => input, "output_tokens" => output, "cost" => cost}
         },
         questions
       )
       when is_binary(model) and is_map(answers) and is_integer(input) and is_integer(output) and
              is_number(cost) do
    usage = %{input_tokens: input, output_tokens: output}
    cost_usd = dollars(cost)

    case Enum.reduce_while(questions, %{}, &read_answer(&1, &2, answers)) do
      {:unexpected_answer, name} ->
        {:error, %Error{reason: {:unexpected_answer, name}, usage: usage, cost_usd: cost_usd}}

      read ->
        {:ok, %Decision{answers: read, model: model, usage: usage, cost_usd: cost_usd}}
    end
  end

  defp answers(_body, _questions), do: {:error, %Error{reason: :unexpected_response}}

  defp read_answer({name, %{choices: choices}}, read, answers) do
    case answers do
      %{^name => %{"choice" => choice} = answer} when is_map_key(choices, choice) ->
        {:cont, Map.put(read, name, %{choice: choice, confidence: confidence(answer)})}

      _other ->
        {:halt, {:unexpected_answer, name}}
    end
  end

  defp confidence(%{"confidence" => confidence}) when is_number(confidence), do: confidence / 1
  defp confidence(_answer), do: nil

  defp dollars(cost) when is_integer(cost), do: Decimal.new(cost)
  defp dollars(cost) when is_float(cost), do: Decimal.from_float(cost)

  defp emit(result, model, duration) do
    {usage, cost_usd} = billed(result)

    :telemetry.execute(
      [:regent_jev, :decide],
      %{
        duration: duration,
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        cost_usd: Decimal.to_float(cost_usd)
      },
      %{model: model, outcome: outcome(result)}
    )
  end

  @unbilled {%{input_tokens: 0, output_tokens: 0}, Decimal.new(0)}

  defp billed({:ok, %Decision{usage: usage, cost_usd: cost_usd}}), do: {usage, cost_usd}
  defp billed({:error, %Error{usage: nil}}), do: @unbilled
  defp billed({:error, %Error{usage: usage, cost_usd: cost_usd}}), do: {usage, cost_usd}

  defp outcome({:ok, _decision}), do: :ok
  defp outcome({:error, %Error{reason: :api_key_missing}}), do: :api_key_missing
  defp outcome({:error, %Error{reason: {:openrouter, _status, _code}}}), do: :http_error
  defp outcome({:error, %Error{reason: {:transport, _message}}}), do: :transport
  defp outcome({:error, %Error{reason: {:unexpected_answer, _name}}}), do: :unexpected_answer
  defp outcome({:error, %Error{reason: :unexpected_response}}), do: :unexpected_response
end

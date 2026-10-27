defmodule RegentAnthropic do
  @moduledoc """
  Claude replies for Regent Elixir apps, through Anthropic's Messages API.

  Every result carries the tokens it used and what they cost in US dollars
  (`RegentAnthropic.Prices`), so the site can record the spend and hold each
  person to its allowance. A model without a known price is refused before
  anything is sent. Nothing is retried, no redirect is followed (so the key only
  ever reaches Anthropic), and inputs and outputs are never logged.

  The app sets the key in `config/runtime.exs`:

      config :regent_anthropic, api_key: System.fetch_env!("ANTHROPIC_API_KEY")

  Requests go through `RegentHttp`, so tests stub the client there.
  """

  alias RegentAnthropic.{Error, Prices, Reply}

  @url "https://api.anthropic.com/v1/messages"
  @version "2023-06-01"
  @receive_timeout 60_000

  @type usage :: %{
          input_tokens: non_neg_integer(),
          cache_write_tokens: non_neg_integer(),
          cache_read_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type input_part :: {:text, String.t()} | {:image, String.t(), binary()}

  @doc """
  Asks a model for a reply, with adaptive thinking.

  Options:

    * `:model` (required) — a model in `RegentAnthropic.Prices`
    * `:system` (required) — the system prompt
    * `:input` (required) — a string, or a list of `{:text, text}` and
      `{:image, media_type, bytes}` parts
    * `:max_tokens` (required) — a ceiling on thinking and reply tokens together
    * `:schema` — a JSON schema; the reply is held to it and decoded into `json`
    * `:effort` — how much the model thinks and writes, such as `"high"`
    * `:receive_timeout` — milliseconds to wait for the reply, 60,000 by default
  """
  @spec respond(keyword()) :: {:ok, Reply.t()} | {:error, Error.t()}
  def respond(opts) do
    model = Keyword.fetch!(opts, :model)

    output_config =
      %{}
      |> put_present(:effort, opts[:effort])
      |> put_present(:format, opts[:schema] && %{type: "json_schema", schema: opts[:schema]})

    body =
      %{
        model: model,
        max_tokens: Keyword.fetch!(opts, :max_tokens),
        system: Keyword.fetch!(opts, :system),
        messages: [%{role: "user", content: content(Keyword.fetch!(opts, :input))}],
        thinking: %{type: "adaptive"}
      }
      |> put_present(:output_config, if(output_config != %{}, do: output_config))

    with {:ok, prices} <- prices(model),
         {:ok, response} <- post(body, opts) do
      reply(response, model, prices, opts[:schema])
    end
  end

  defp content(text) when is_binary(text), do: text
  defp content(parts) when is_list(parts), do: Enum.map(parts, &part/1)

  defp part({:text, text}), do: %{type: "text", text: text}

  defp part({:image, media_type, bytes}) do
    %{
      type: "image",
      source: %{type: "base64", media_type: media_type, data: Base.encode64(bytes)}
    }
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp prices(model) do
    case Prices.fetch(model) do
      {:ok, prices} -> {:ok, prices}
      :error -> {:error, %Error{reason: {:unpriced_model, model}}}
    end
  end

  defp post(body, opts) do
    with {:ok, api_key} <- api_key() do
      @url
      |> RegentHttp.post(
        json: body,
        headers: [{"x-api-key", api_key}, {"anthropic-version", @version}],
        retry: false,
        redirect: false,
        receive_timeout: Keyword.get(opts, :receive_timeout, @receive_timeout)
      )
      |> handle_response()
    end
  end

  defp api_key do
    case Application.get_env(:regent_anthropic, :api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, %Error{reason: :api_key_missing}}
    end
  end

  defp handle_response({:ok, %{status: 200, body: body}}), do: {:ok, body}

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error,
     %Error{reason: {:anthropic, status, error_field(body, "type"), error_field(body, "message")}}}
  end

  defp handle_response({:error, reason}) do
    {:error, %Error{reason: {:transport, RegentHttp.format_error(reason)}}}
  end

  defp error_field(%{"error" => %{} = error}, field) do
    case error[field] do
      value when is_binary(value) -> value
      _missing -> nil
    end
  end

  defp error_field(_body, _field), do: nil

  defp reply(
         %{
           "id" => id,
           "content" => content,
           "stop_reason" => stop,
           "usage" => %{"input_tokens" => input, "output_tokens" => output} = raw
         },
         model,
         prices,
         schema
       )
       when is_list(content) and is_integer(input) and is_integer(output) do
    usage = %{
      input_tokens: input,
      cache_write_tokens: raw["cache_creation_input_tokens"] || 0,
      cache_read_tokens: raw["cache_read_input_tokens"] || 0,
      output_tokens: output
    }

    cost =
      Prices.cost(prices,
        input: usage.input_tokens,
        cache_write: usage.cache_write_tokens,
        cache_read: usage.cache_read_tokens,
        output: usage.output_tokens
      )

    text = for %{"type" => "text", "text" => text} <- content, into: "", do: text
    billed = %Error{usage: usage, cost_usd: cost}

    case stop do
      "end_turn" ->
        case decode_json(text, schema) do
          {:ok, json} ->
            {:ok,
             %Reply{
               text: text,
               json: json,
               message_id: id,
               model: model,
               usage: usage,
               cost_usd: cost
             }}

          :error ->
            {:error, %{billed | reason: :invalid_json}}
        end

      "refusal" ->
        {:error, %{billed | reason: :refused}}

      other ->
        {:error, %{billed | reason: {:incomplete, other}}}
    end
  end

  defp reply(_body, _model, _prices, _schema), do: {:error, %Error{reason: :unexpected_response}}

  defp decode_json(_text, nil), do: {:ok, nil}

  defp decode_json(text, _schema) do
    case Jason.decode(text) do
      {:ok, json} when is_map(json) -> {:ok, json}
      _invalid -> :error
    end
  end
end

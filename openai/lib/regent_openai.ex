defmodule RegentOpenAI do
  @moduledoc """
  OpenAI text replies, transcription and speech for Regent Elixir apps.

  Every result carries the tokens it used and what they cost in US dollars
  (`RegentOpenAI.Prices`), so the site can record the spend and hold each person
  to its allowance. A model without a known price is refused before anything is
  sent. Nothing is stored at OpenAI (`store: false`), nothing is retried, and
  inputs and outputs are never logged.

  The app sets the key in `config/runtime.exs`:

      config :regent_openai, api_key: System.fetch_env!("OPENAI_API_KEY")

  Requests go through `RegentHttp`, so tests stub the client there.
  """

  alias RegentOpenAI.{Error, Prices, Reply, Speech, Transcript}

  @base_url "https://api.openai.com/v1"
  @receive_timeout 60_000
  @max_audio_bytes 25 * 1024 * 1024
  @max_speech_characters 4096

  @speech_content_types %{
    "mp3" => "audio/mpeg",
    "opus" => "audio/ogg",
    "aac" => "audio/aac",
    "flac" => "audio/flac",
    "wav" => "audio/wav",
    "pcm" => "audio/pcm"
  }

  @type usage :: %{
          input_tokens: non_neg_integer(),
          cached_input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type input_part :: {:text, String.t()} | {:image_url, String.t()}

  @doc """
  Asks a model for a reply (the Responses API).

  Options:

    * `:model` (required) — a model in `RegentOpenAI.Prices`
    * `:instructions` (required) — the system prompt
    * `:input` (required) — a string, or a list of `{:text, text}` and
      `{:image_url, url}` parts; `image_data_url/2` turns a screenshot into a url
    * `:schema` — `{name, json_schema}`; the reply is held to it and decoded into `json`
    * `:reasoning` — the reasoning effort, such as `"low"`
    * `:max_output_tokens` — a ceiling on reasoning and reply tokens together
    * `:receive_timeout` — milliseconds to wait for the reply, 60,000 by default
  """
  @spec respond(keyword()) :: {:ok, Reply.t()} | {:error, Error.t()}
  def respond(opts) do
    model = Keyword.fetch!(opts, :model)

    body =
      %{
        model: model,
        instructions: Keyword.fetch!(opts, :instructions),
        input: input(Keyword.fetch!(opts, :input)),
        store: false
      }
      |> put_present(:reasoning, opts[:reasoning] && %{effort: opts[:reasoning]})
      |> put_present(:max_output_tokens, opts[:max_output_tokens])
      |> put_present(:text, text_format(opts[:schema]))

    with {:ok, prices} <- prices(model),
         {:ok, response} <- post("/responses", [json: body], opts) do
      reply(response, model, prices, opts[:schema])
    end
  end

  @doc """
  Turns speech into text (for push-to-talk).

  Options: `:model` (required), `:filename` and `:content_type` (required, as the
  browser recorded it, such as `"clip.webm"` and `"audio/webm"`), `:language`
  (an ISO-639-1 code), `:prompt` and `:receive_timeout`. Audio over 25 MB is
  refused before sending.
  """
  @spec transcribe(binary(), keyword()) :: {:ok, Transcript.t()} | {:error, Error.t()}
  def transcribe(audio, opts) when is_binary(audio) do
    model = Keyword.fetch!(opts, :model)

    file =
      {audio,
       filename: Keyword.fetch!(opts, :filename),
       content_type: Keyword.fetch!(opts, :content_type),
       size: byte_size(audio)}

    fields =
      [file: file, model: model]
      |> put_present_field(:language, opts[:language])
      |> put_present_field(:prompt, opts[:prompt])

    with {:ok, prices} <- prices(model),
         :ok <- within(byte_size(audio), @max_audio_bytes, :audio_too_large),
         {:ok, response} <- post("/audio/transcriptions", [form_multipart: fields], opts) do
      transcript(response, model, prices)
    end
  end

  @doc """
  Turns text into spoken audio.

  Options: `:model` (required), `:voice` (required, such as `"marin"`),
  `:instructions` (how to speak), `:format` (`"mp3"` by default; also `"opus"`,
  `"aac"`, `"flac"`, `"wav"` or `"pcm"`) and `:receive_timeout`. Text over 4,096
  characters is refused before sending.
  """
  @spec speak(String.t(), keyword()) :: {:ok, Speech.t()} | {:error, Error.t()}
  def speak(text, opts) when is_binary(text) do
    model = Keyword.fetch!(opts, :model)
    format = Keyword.get(opts, :format, "mp3")
    content_type = Map.fetch!(@speech_content_types, format)

    body =
      %{
        model: model,
        input: text,
        voice: Keyword.fetch!(opts, :voice),
        response_format: format,
        stream_format: "sse"
      }
      |> put_present(:instructions, opts[:instructions])

    with {:ok, prices} <- prices(model),
         :ok <- within(String.length(text), @max_speech_characters, :text_too_long),
         {:ok, events} <- post("/audio/speech", [json: body], opts) do
      speech(events, model, content_type, prices)
    end
  end

  @doc "A `data:` url for an image, to pass as `{:image_url, url}`."
  @spec image_data_url(binary(), String.t()) :: String.t()
  def image_data_url(image, content_type) when is_binary(image) do
    "data:#{content_type};base64," <> Base.encode64(image)
  end

  defp input(text) when is_binary(text), do: text
  defp input(parts) when is_list(parts), do: [%{role: "user", content: Enum.map(parts, &part/1)}]

  defp part({:text, text}), do: %{type: "input_text", text: text}
  defp part({:image_url, url}), do: %{type: "input_image", image_url: url}

  defp text_format(nil), do: nil

  defp text_format({name, schema}) do
    %{format: %{type: "json_schema", name: name, strict: true, schema: schema}}
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp put_present_field(fields, _key, nil), do: fields
  defp put_present_field(fields, key, value), do: fields ++ [{key, value}]

  defp prices(model) do
    case Prices.fetch(model) do
      {:ok, prices} -> {:ok, prices}
      :error -> {:error, %Error{reason: {:unpriced_model, model}}}
    end
  end

  defp within(size, limit, _reason) when size <= limit, do: :ok
  defp within(size, _limit, reason), do: {:error, %Error{reason: {reason, size}}}

  defp post(path, body, opts) do
    with {:ok, api_key} <- api_key() do
      (@base_url <> path)
      |> RegentHttp.post(
        [
          auth: {:bearer, api_key},
          retry: false,
          receive_timeout: Keyword.get(opts, :receive_timeout, @receive_timeout)
        ] ++ body
      )
      |> handle_response()
    end
  end

  defp api_key do
    case Application.get_env(:regent_openai, :api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, %Error{reason: :api_key_missing}}
    end
  end

  defp handle_response({:ok, %{status: 200, body: body}}), do: {:ok, body}

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, %Error{reason: {:openai, status, error_code(body)}}}
  end

  defp handle_response({:error, reason}) do
    {:error, %Error{reason: {:transport, RegentHttp.format_error(reason)}}}
  end

  defp error_code(%{"error" => %{"code" => code}}) when is_binary(code), do: code
  defp error_code(%{"error" => %{"type" => type}}) when is_binary(type), do: type
  defp error_code(_body), do: nil

  defp reply(
         %{"id" => id, "status" => status, "output" => output, "usage" => raw} = body,
         model,
         prices,
         schema
       ) do
    usage = %{
      input_tokens: raw["input_tokens"],
      cached_input_tokens: raw["input_tokens_details"]["cached_tokens"],
      output_tokens: raw["output_tokens"]
    }

    cost =
      Prices.cost(prices,
        input: usage.input_tokens - usage.cached_input_tokens,
        cached_input: usage.cached_input_tokens,
        output: usage.output_tokens
      )

    parts = for %{"type" => "message", "content" => content} <- output, part <- content, do: part
    text = for %{"type" => "output_text", "text" => text} <- parts, into: "", do: text
    refusal = for %{"type" => "refusal", "refusal" => refusal} <- parts, into: "", do: refusal
    billed = %Error{usage: usage, cost_usd: cost}

    cond do
      status == "incomplete" ->
        {:error, %{billed | reason: {:incomplete, body["incomplete_details"]["reason"]}}}

      refusal != "" ->
        {:error, %{billed | reason: {:refused, refusal}}}

      status != "completed" ->
        {:error, %{billed | reason: :unexpected_response}}

      true ->
        case decode_json(text, schema) do
          {:ok, json} ->
            {:ok,
             %Reply{
               text: text,
               json: json,
               response_id: id,
               model: model,
               usage: usage,
               cost_usd: cost
             }}

          :error ->
            {:error, %{billed | reason: :invalid_json}}
        end
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

  defp transcript(%{"text" => text, "usage" => %{"type" => "tokens"} = raw}, model, prices) do
    usage = %{
      input_tokens: raw["input_tokens"],
      cached_input_tokens: 0,
      output_tokens: raw["output_tokens"]
    }

    {:ok,
     %Transcript{
       text: text,
       model: model,
       usage: usage,
       cost_usd: Prices.cost(prices, input: usage.input_tokens, output: usage.output_tokens)
     }}
  end

  defp transcript(_body, _model, _prices), do: {:error, %Error{reason: :unexpected_response}}

  # With `stream_format: "sse"` the audio arrives as base64 `speech.audio.delta`
  # events and the usage on the closing `speech.audio.done` event.
  defp speech(events, model, content_type, prices) when is_binary(events) do
    decoded =
      for "data: " <> data <- String.split(events, ["\r\n", "\n"]),
          {:ok, event} <- [Jason.decode(data)],
          do: event

    audio =
      for %{"type" => "speech.audio.delta", "audio" => chunk} <- decoded,
          into: "",
          do: Base.decode64!(chunk)

    case for(%{"type" => "speech.audio.done", "usage" => raw} <- decoded, do: raw) do
      [%{"input_tokens" => input, "output_tokens" => output}] ->
        usage = %{input_tokens: input, cached_input_tokens: 0, output_tokens: output}

        {:ok,
         %Speech{
           audio: audio,
           content_type: content_type,
           model: model,
           usage: usage,
           cost_usd: Prices.cost(prices, input: input, output: output)
         }}

      _missing ->
        {:error, %Error{reason: :unexpected_response}}
    end
  end

  defp speech(_body, _model, _content_type, _prices),
    do: {:error, %Error{reason: :unexpected_response}}
end

defmodule RegentChatGPT.Codex do
  @moduledoc """
  ChatGPT-backed Codex transport helpers.

  This module builds URLs, headers, and normalized request bodies. It does not
  decide product authorization, rate limits, storage, or billing policy.
  """

  alias RegentChatGPT.{Config, Error, HTTP, TokenSet}

  @default_instructions "You are a helpful assistant powered by the user's connected ChatGPT account. Answer directly and helpfully."
  @default_model "gpt-5.5"
  @reasoning_encrypted_content "reasoning.encrypted_content"

  @type response_options :: [
          instructions: String.t(),
          reasoning_effort: String.t(),
          reasoning_summary: String.t(),
          text_verbosity: String.t(),
          service_tier: String.t()
        ]

  @spec normalize_responses_body(map(), response_options()) :: map()
  def normalize_responses_body(body, opts \\ []) when is_map(body) do
    body
    |> ensure_instructions(opts)
    |> Map.put("store", false)
    |> put_reasoning(opts)
    |> put_text(opts)
    |> put_service_tier(opts)
    |> put_include()
    |> filter_input()
    |> Map.delete("max_output_tokens")
    |> Map.delete("max_completion_tokens")
  end

  @spec responses_request(
          Config.t() | keyword() | map(),
          TokenSet.t() | map(),
          map(),
          response_options()
        ) ::
          {:ok, keyword()} | {:error, Error.t()}
  def responses_request(config, tokens, body, opts \\ []) do
    config = Config.resolve(config)
    token_set = TokenSet.from(tokens)

    cond do
      not is_map(body) ->
        {:error, Error.new(:invalid_responses_request, "Expected a JSON object body.")}

      not is_binary(token_set && token_set.access_token) or
          not is_binary(token_set && token_set.account_id) ->
        {:error,
         Error.new(:not_authenticated, "ChatGPT credentials are missing account authorization.")}

      true ->
        body =
          body
          |> Map.put_new("model", Keyword.get(opts, :default_model, @default_model))
          |> normalize_responses_body(opts)

        {:ok,
         [
           method: :post,
           url:
             "/responses"
             |> resolve_target_url(config.codex_base_url)
             |> with_client_version(config.client_version),
           headers:
             auth_headers(config, token_set, [
               {"content-type", "application/json"},
               {"accept", "text/event-stream"}
             ]),
           body: Jason.encode!(body)
         ]}
    end
  end

  @spec list_models(Config.t() | keyword() | map(), TokenSet.t() | map()) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  def list_models(config, tokens) do
    config = Config.resolve(config)
    token_set = TokenSet.from(tokens)

    if token_set && is_binary(token_set.access_token) && is_binary(token_set.account_id) do
      url = "#{config.codex_base_url}/models" |> with_client_version(config.client_version)

      with {:ok, response} <-
             HTTP.request(config,
               method: :get,
               url: url,
               headers: auth_headers(config, token_set, [{"accept", "application/json"}])
             ),
           {:ok, body} <- decode_json(response) do
        if ok_status?(response) do
          {:ok, extract_model_slugs(body)}
        else
          {:error,
           Error.new(:models_request_failed, "Model list request failed.",
             status: response.status,
             body: response_body(response)
           )}
        end
      else
        {:error, %Error{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error,
           Error.new(:network_error, "Failed to reach the Codex models endpoint.",
             body: inspect(reason)
           )}
      end
    else
      {:error,
       Error.new(:not_authenticated, "ChatGPT credentials are missing account authorization.")}
    end
  end

  @spec extract_model_slugs(term()) :: [String.t()]
  def extract_model_slugs(value) do
    candidates =
      cond do
        is_list(value) ->
          value

        is_map(value) ->
          Enum.find_value(
            ["models", "data", "items", "available_models"],
            [],
            &list_field(value, &1)
          )

        true ->
          []
      end

    candidates
    |> Enum.reduce([], fn item, acc ->
      case model_slug(item) do
        slug when is_binary(slug) and slug != "" ->
          if slug in acc, do: acc, else: acc ++ [slug]

        _slug ->
          acc
      end
    end)
  end

  @spec auth_headers(Config.t(), TokenSet.t(), [{String.t(), String.t()}]) :: [
          {String.t(), String.t()}
        ]
  def auth_headers(config, %TokenSet{} = tokens, extra_headers \\ []) do
    extra_headers ++
      [
        {"authorization", "Bearer #{tokens.access_token}"},
        {"chatgpt-account-id", tokens.account_id},
        {"openai-beta", "responses=experimental"},
        {"originator", config.originator}
      ]
  end

  @spec resolve_target_url(String.t(), String.t()) :: String.t()
  def resolve_target_url(input, codex_base_url) do
    base = URI.parse(codex_base_url)
    base_path = base.path |> to_string() |> String.replace(~r{/+$}, "")

    parsed =
      if String.starts_with?(input, ["http://", "https://"]),
        do: URI.parse(input),
        else: URI.parse(input)

    path = parsed.path || "/"

    path =
      cond do
        base_path != "" and String.starts_with?(path, "#{base_path}/") ->
          String.slice(path, String.length(base_path)..-1//1)

        path == "/v1" ->
          "/"

        String.starts_with?(path, "/v1/") ->
          String.slice(path, 3..-1//1)

        String.starts_with?(path, "/") ->
          path

        true ->
          "/#{path}"
      end

    %URI{base | path: base_path <> path, query: parsed.query}
    |> URI.to_string()
  end

  @spec with_client_version(String.t(), String.t() | nil) :: String.t()
  def with_client_version(url, nil), do: url
  def with_client_version(url, ""), do: url

  def with_client_version(url, client_version) do
    uri = URI.parse(url)
    params = URI.decode_query(uri.query || "")

    if Map.has_key?(params, "client_version") do
      url
    else
      %{uri | query: URI.encode_query(Map.put(params, "client_version", client_version))}
      |> URI.to_string()
    end
  end

  defp ensure_instructions(body, opts) do
    case body["instructions"] do
      value when is_binary(value) -> body
      _ -> Map.put(body, "instructions", Keyword.get(opts, :instructions, @default_instructions))
    end
  end

  defp put_reasoning(body, opts) do
    defaults = %{
      "effort" => Keyword.get(opts, :reasoning_effort, "medium"),
      "summary" => Keyword.get(opts, :reasoning_summary, "auto")
    }

    Map.put(body, "reasoning", Map.merge(defaults, map_field(body, "reasoning")))
  end

  defp put_text(body, opts) do
    defaults = %{"verbosity" => Keyword.get(opts, :text_verbosity, "medium")}
    Map.put(body, "text", Map.merge(defaults, map_field(body, "text")))
  end

  defp put_service_tier(body, opts) do
    case {body["service_tier"], Keyword.get(opts, :service_tier)} do
      {value, _tier} when is_binary(value) -> body
      {_value, tier} when is_binary(tier) -> Map.put(body, "service_tier", tier)
      _ -> body
    end
  end

  defp put_include(body) do
    include =
      body
      |> Map.get("include", [])
      |> List.wrap()
      |> Enum.filter(&is_binary/1)

    include =
      if @reasoning_encrypted_content in include,
        do: include,
        else: include ++ [@reasoning_encrypted_content]

    Map.put(body, "include", include)
  end

  defp filter_input(%{"input" => input} = body) when is_list(input) do
    Map.put(body, "input", Enum.flat_map(input, &filter_input_item/1))
  end

  defp filter_input(body), do: body

  defp filter_input_item(%{"type" => "item_reference"}), do: []
  defp filter_input_item(%{type: "item_reference"}), do: []

  defp filter_input_item(item) when is_map(item),
    do: [item |> Map.delete("id") |> Map.delete(:id)]

  defp filter_input_item(item), do: [item]

  defp map_field(body, key) do
    case body[key] do
      value when is_map(value) -> value
      _ -> %{}
    end
  end

  defp list_field(map, key) do
    case map[key] do
      value when is_list(value) -> value
      _ -> nil
    end
  end

  defp model_slug(item) when is_binary(item), do: String.trim(item)

  defp model_slug(item) when is_map(item) do
    ["slug", "id", "model", "name"]
    |> Enum.find_value(fn key ->
      case item[key] do
        value when is_binary(value) -> String.trim(value)
        _ -> nil
      end
    end)
  end

  defp model_slug(_item), do: nil

  defp decode_json(%{body: body}) when is_map(body), do: {:ok, body}

  defp decode_json(%{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:error, Error.new(:models_request_failed, "Codex endpoint returned invalid JSON.")}
    end
  end

  defp decode_json(_response), do: {:ok, %{}}

  defp ok_status?(%{status: status}) when is_integer(status), do: status >= 200 and status < 300

  defp response_body(%{body: body}) when is_binary(body), do: body
  defp response_body(%{body: body}), do: inspect(body)
  defp response_body(_response), do: nil
end

defmodule Siwa.Captcha do
  @behaviour Siwa.CaptchaPolicy

  @difficulty_defaults %{
    "easy" => %{time_limit_seconds: 30, line_count: 3, ascii_target: 240},
    "medium" => %{time_limit_seconds: 20, line_count: 4, ascii_target: 332, word_count: 14},
    "hard" => %{time_limit_seconds: 18, line_count: 4, ascii_target: 360, word_count: 18},
    "extreme" => %{time_limit_seconds: 15, line_count: 5, ascii_target: 410, word_count: 22}
  }

  def challenge(_params, opts \\ []) do
    difficulty = Keyword.get(opts, :difficulty, "medium")
    {:ok, challenge} = create_challenge(difficulty, opts)
    {:ok, challenge.challenge}
  end

  def verify(challenge, response, _opts \\ []) do
    if is_binary(response) and response != "" and matches_ascii_target?(challenge, response) do
      {:ok, %{status: "captcha_solved"}}
    else
      {:error, :captcha_failed}
    end
  end

  def create_challenge(difficulty, opts \\ []) do
    config = Map.fetch!(@difficulty_defaults, to_string(difficulty))
    created_at = Keyword.get(opts, :created_at, System.system_time(:millisecond))

    secret =
      Keyword.get_lazy(opts, :secret, fn -> Application.fetch_env!(:siwa, :nonce_secret) end)

    challenge =
      %{
        "topic" => Keyword.get(opts, :topic, "AI agents and trust"),
        "format" => Keyword.get(opts, :format, "quatrain"),
        "lineCount" => Keyword.get(opts, :line_count, config.line_count),
        "asciiTarget" => Keyword.get(opts, :ascii_target, config.ascii_target),
        "timeLimitSeconds" => Keyword.get(opts, :time_limit_seconds, config.time_limit_seconds),
        "difficulty" => to_string(difficulty),
        "createdAt" => created_at
      }
      |> maybe_put("wordCount", config[:word_count])

    token = sign_challenge(challenge, secret)
    {:ok, %{challenge: challenge, challenge_token: token}}
  end

  def pack_response(challenge_token, text, solved_at \\ System.system_time(:millisecond)) do
    payload = %{
      "challengeToken" => challenge_token,
      "solution" => %{"text" => text, "solvedAt" => solved_at}
    }

    payload
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  def unpack_response(packed) do
    with {:ok, body} <- Base.url_decode64(packed, padding: false),
         {:ok, payload} <- Jason.decode(body) do
      {:ok,
       %{
         challenge_token: payload["challengeToken"],
         solution: payload["solution"]
       }}
    else
      _ -> {:error, :invalid_captcha_response}
    end
  end

  def verify_challenge(challenge_token, solution, secret, opts \\ []) do
    with {:ok, challenge} <- verify_challenge_token(challenge_token, secret),
         :ok <- maybe_consume(challenge_token, opts) do
      {:ok, evaluate_solution(challenge, solution, opts)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp matches_ascii_target?(challenge, response) do
    lines = String.split(response, "\n", trim: true)
    target = challenge["asciiTarget"] || challenge[:ascii_target]
    line_count = challenge["lineCount"] || challenge[:line_count]

    Enum.count(lines) == line_count and
      Enum.reduce(lines, 0, fn line, sum -> sum + first_char_ascii(line) end) == target
  end

  defp first_char_ascii(<<char::utf8, _rest::binary>>), do: char
  defp first_char_ascii(_), do: 0

  defp sign_challenge(challenge, secret) do
    encoded = Jason.encode!(challenge) |> Base.url_encode64(padding: false)
    mac = :crypto.mac(:hmac, :sha256, secret, encoded) |> Base.url_encode64(padding: false)
    encoded <> "." <> mac
  end

  defp verify_challenge_token(token, secret) do
    with [encoded, mac] <- String.split(token, ".", parts: 2),
         expected <-
           :crypto.mac(:hmac, :sha256, secret, encoded) |> Base.url_encode64(padding: false),
         true <- Plug.Crypto.secure_compare(expected, mac),
         {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, challenge} <- Jason.decode(json) do
      {:ok, challenge}
    else
      _ -> {:error, :invalid_challenge_token}
    end
  end

  defp maybe_consume(challenge_token, opts) do
    case Keyword.get(opts, :consume_challenge) do
      nil ->
        :ok

      fun when is_function(fun, 1) ->
        if fun.(challenge_token), do: :ok, else: {:error, :replayed_challenge}
    end
  end

  defp evaluate_solution(challenge, solution, opts) do
    text = solution["text"] || solution[:text] || ""

    solved_at =
      solution["solvedAt"] || solution[:solved_at] || solution[:solvedAt] ||
        System.system_time(:millisecond)

    lines = String.split(text, "\n", trim: true)
    ascii_target = challenge["asciiTarget"]
    ascii_actual = Enum.reduce(lines, 0, fn line, sum -> sum + first_char_ascii(line) end)
    line_target = challenge["lineCount"]
    line_actual = Enum.count(lines)
    word_target = challenge["wordCount"]
    word_actual = count_words(text)
    elapsed = max(div(solved_at - challenge["createdAt"], 1_000), 0)
    timing_tolerance = Keyword.get(opts, :timing_tolerance_seconds, 2)

    ascii_pass = ascii_actual == ascii_target
    line_pass = line_actual == line_target

    word_result =
      if is_nil(word_target) do
        nil
      else
        %{pass: word_actual == word_target, actual: word_actual, target: word_target}
      end

    overall =
      ascii_pass and line_pass and
        (is_nil(word_result) or word_result.pass) and
        elapsed <= challenge["timeLimitSeconds"] + timing_tolerance

    %{
      asciiSum: %{pass: ascii_pass, actual: ascii_actual, target: ascii_target},
      timing: %{
        pass: elapsed <= challenge["timeLimitSeconds"] + timing_tolerance,
        elapsedSeconds: elapsed
      },
      overallPass: overall,
      verdict: if(overall, do: "VERIFIED_AI_AGENT", else: "CHALLENGE_FAILED"),
      lineCount: %{pass: line_pass, actual: line_actual, target: line_target}
    }
    |> maybe_put(:wordCount, word_result)
  end

  defp count_words(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.count()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

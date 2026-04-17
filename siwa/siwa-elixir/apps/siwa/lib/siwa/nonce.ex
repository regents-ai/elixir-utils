defmodule Siwa.Nonce do
  alias Siwa.{Captcha, Registry}

  @default_ttl_ms 5 * 60 * 1_000

  def issue(params, opts \\ []) do
    params = normalize(params)
    store = Keyword.get(opts, :store, Application.fetch_env!(:siwa, :nonce_store))
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    issued_at = DateTime.truncate(now, :second)
    expiration_time = DateTime.add(issued_at, div(ttl_ms, 1_000), :second)

    with :ok <- ensure_registry(params.agent_registry),
         :ok <- maybe_validate_registration(params, opts) do
      case maybe_handle_captcha(params, opts, now) do
        :ok ->
      nonce = generate_nonce(16)
      metadata = %{
        address: params.address,
        agent_id: params.agent_id,
        agent_registry: params.agent_registry,
        issued_at: issued_at,
        expiration_time: expiration_time
      }

      case store_nonce(store, params, nonce, metadata) do
        :ok ->
          nonce_token =
            case Keyword.get_lazy(opts, :nonce_secret, fn -> Keyword.get(opts, :secret) end) do
              nil ->
                nil

              secret ->
                {:ok, token} =
                  create_nonce_token(%{
                    "nonce" => nonce,
                    "address" => params.address,
                    "agentId" => params.agent_id,
                    "iat" => DateTime.to_unix(issued_at, :millisecond),
                    "exp" => DateTime.to_unix(expiration_time, :millisecond)
                  }, secret: secret)

                token
            end

          {:ok,
           %{
             nonce: nonce,
             nonce_token: nonce_token,
             issued_at: DateTime.to_iso8601(issued_at),
             expiration_time: DateTime.to_iso8601(expiration_time),
             status: "nonce_issued"
           }}

        {:error, reason} -> {:error, reason}
      end

        {:captcha_required, payload} ->
          {:ok, payload}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def consume(params, opts \\ []) do
    params = normalize(params)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    case Keyword.get(opts, :nonce_token) do
      nil ->
        store = Keyword.get(opts, :store, Application.fetch_env!(:siwa, :nonce_store))

        with {:ok, stored} <- consume_nonce(store, params),
             :ok <- validate_entry(stored, params, now) do
          {:ok, stored}
        end

      token ->
        nonce_secret =
          Keyword.get_lazy(opts, :nonce_secret, fn ->
            Keyword.fetch!(opts, :secret)
          end)

        with {:ok, stored} <- verify_nonce_token(token, nonce_secret: nonce_secret, now: now),
             :ok <- validate_token_entry(stored, params) do
          {:ok, stored}
        end
    end
  end

  def generate_nonce(length \\ 16) do
    Base.url_encode64(Siwa.Crypto.random_bytes(length), padding: false)
    |> binary_part(0, length)
  end

  def create_nonce_token(payload, opts \\ []) do
    secret =
      Keyword.get_lazy(opts, :nonce_secret, fn ->
        Keyword.get(opts, :secret, Application.fetch_env!(:siwa, :nonce_secret))
      end)

    body = Jason.encode!(payload)
    encoded_body = Base.url_encode64(body, padding: false)
    mac = :crypto.mac(:hmac, :sha256, secret, encoded_body) |> Base.url_encode64(padding: false)
    {:ok, encoded_body <> "." <> mac}
  end

  def verify_nonce_token(token, opts \\ []) do
    secret =
      Keyword.get_lazy(opts, :nonce_secret, fn ->
        Keyword.get(opts, :secret, Application.fetch_env!(:siwa, :nonce_secret))
      end)

    now_ms = opts |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end) |> DateTime.to_unix(:millisecond)

    with [encoded_body, mac] <- String.split(token, ".", parts: 2),
         expected <- :crypto.mac(:hmac, :sha256, secret, encoded_body) |> Base.url_encode64(padding: false),
         true <- Plug.Crypto.secure_compare(expected, mac),
         {:ok, body} <- Base.url_decode64(encoded_body, padding: false),
         {:ok, payload} <- Jason.decode(body),
         true <- payload["exp"] >= now_ms do
      {:ok, payload}
    else
      _ -> {:error, :invalid_nonce_token}
    end
  end

  defp ensure_registry(agent_registry) do
    case Registry.parse_agent_registry(agent_registry) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp maybe_handle_captcha(params, opts, now) do
    response = Map.get(params, :challenge_response) || Map.get(params, "challenge_response")

    case resolve_captcha_requirement(params, opts, now) do
      nil ->
        :ok

      %{challenge: challenge, challenge_token: token, secret: secret} ->
        case response do
          nil ->
            {:captcha_required,
             %{
               status: "captcha_required",
               challenge: challenge,
               challenge_token: token
             }}

          packed ->
            with {:ok, unpacked} <- Captcha.unpack_response(packed),
                 true <- unpacked.challenge_token == token,
                 {:ok, verified} <- Captcha.verify_challenge(token, unpacked.solution, secret, timing_tolerance_seconds: 2),
                 true <- verified.overallPass do
              :ok
            else
              false -> {:error, :captcha_failed}
              {:error, _reason} -> {:error, :captcha_failed}
            end
        end
    end
  end

  defp resolve_captcha_requirement(params, opts, now) do
    created_at = DateTime.to_unix(now, :millisecond)
    captcha_secret = Keyword.get(opts, :captcha_secret, Application.fetch_env!(:siwa, :nonce_secret))

    case Keyword.get(opts, :captcha_policy) do
      nil ->
        case Keyword.get(opts, :captcha) do
          nil ->
            nil

          %{challenge: challenge, challenge_token: token} ->
            %{challenge: challenge, challenge_token: token, secret: captcha_secret}

          challenge when is_map(challenge) ->
            token =
              case Captcha.create_challenge(Map.get(challenge, "difficulty", "medium"),
                     secret: captcha_secret,
                     topic: Map.get(challenge, "topic", "AI agents and trust"),
                     format: Map.get(challenge, "format", "quatrain"),
                     created_at: created_at
                   ) do
                {:ok, generated} -> generated.challenge_token
              end

            %{challenge: challenge, challenge_token: token, secret: captcha_secret}
        end

      policy when is_function(policy, 1) ->
        case policy.(%{address: params.address, agentId: params.agent_id, agentRegistry: params.agent_registry}) do
          nil ->
            nil

          difficulty ->
            {:ok, generated} =
              Captcha.create_challenge(difficulty,
                secret: captcha_secret,
                topic: Keyword.get(opts, :captcha_topic, "AI agents and trust"),
                format: Keyword.get(opts, :captcha_format, "quatrain"),
                created_at: created_at
              )

            Map.put(generated, :secret, captcha_secret)
        end

      module when is_atom(module) ->
        case module.challenge(%{address: params.address, agentId: params.agent_id, agentRegistry: params.agent_registry}, opts) do
          {:ok, challenge} ->
            token =
              case Captcha.create_challenge(Map.get(challenge, "difficulty", "medium"),
                     secret: captcha_secret,
                     topic: Map.get(challenge, "topic", "AI agents and trust"),
                     format: Map.get(challenge, "format", "quatrain"),
                     created_at: created_at
                   ) do
                {:ok, generated} -> generated.challenge_token
              end

            %{challenge: challenge, challenge_token: token, secret: captcha_secret}

          _ ->
            nil
        end
    end
  end

  defp maybe_validate_registration(params, opts) do
    case Keyword.get(opts, :registration_validator) do
      nil -> :ok
      fun when is_function(fun, 1) -> fun.(params)
      module -> module.validate_registration(params, opts)
    end
  end

  defp store_nonce(store, params, nonce, metadata) when is_atom(store) do
    store.put(key(params), nonce, metadata)
  end

  defp store_nonce(fun, params, nonce, metadata) when is_function(fun, 4), do: fun.(key(params), nonce, metadata, params)

  defp consume_nonce(store, params) when is_atom(store) do
    store.consume(key(params), params.nonce)
  end

  defp consume_nonce(fun, params) when is_function(fun, 2), do: fun.(key(params), params.nonce)

  defp validate_entry(entry, params, now) do
    now_ms = DateTime.to_unix(now, :millisecond)
    exp_ms = entry.expiration_time |> DateTime.to_unix(:millisecond)

    cond do
      String.downcase(entry.address) != String.downcase(params.address) -> {:error, :nonce_address_mismatch}
      entry.agent_id != params.agent_id -> {:error, :nonce_agent_id_mismatch}
      entry.agent_registry != params.agent_registry -> {:error, :nonce_registry_mismatch}
      now_ms > exp_ms -> {:error, :nonce_expired}
      true -> :ok
    end
  end

  defp validate_token_entry(entry, params) do
    cond do
      String.downcase(entry["address"]) != String.downcase(params.address) -> {:error, :nonce_address_mismatch}
      entry["agentId"] != params.agent_id -> {:error, :nonce_agent_id_mismatch}
      entry["nonce"] != params.nonce -> {:error, :nonce_mismatch}
      true -> :ok
    end
  end

  defp key(params), do: Enum.join([String.downcase(params.address), params.agent_id, String.downcase(params.agent_registry)], ":")

  defp normalize(params) when is_map(params), do: Map.new(params, fn {k, v} -> {normalize_key(k), v} end)
  defp normalize(params) when is_list(params), do: params |> Enum.into(%{}) |> normalize()

  defp normalize_key("agentId"), do: :agent_id
  defp normalize_key("agentRegistry"), do: :agent_registry
  defp normalize_key("challengeResponse"), do: :challenge_response
  defp normalize_key(key) when is_binary(key), do: String.to_atom(key)
  defp normalize_key(key), do: key
end

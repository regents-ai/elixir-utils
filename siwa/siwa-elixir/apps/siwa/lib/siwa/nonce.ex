defmodule Siwa.Nonce do
  alias Siwa.{Captcha, Registry}

  @default_ttl_ms 5 * 60 * 1_000

  def issue(params, opts \\ []) do
    params = normalize(params)
    store = Keyword.get_lazy(opts, :store, fn -> Application.fetch_env!(:siwa, :nonce_store) end)
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    issued_at = DateTime.truncate(now, :second)
    expiration_time = DateTime.add(issued_at, div(ttl_ms, 1_000), :second)

    with :ok <- ensure_audience(Map.get(params, :audience)),
         :ok <- ensure_registry(Map.get(params, :agent_registry)),
         :ok <- maybe_validate_registration(params, opts) do
      case maybe_handle_captcha(params, opts, now) do
        :ok ->
          nonce = generate_nonce(16)

          metadata = %{
            address: params.address,
            agent_id: params.agent_id,
            agent_registry: params.agent_registry,
            audience: params.audience,
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
                      create_nonce_token(
                        %{
                          "nonce" => nonce,
                          "address" => params.address,
                          "agent_id" => params.agent_id,
                          "agent_registry" => params.agent_registry,
                          "audience" => params.audience,
                          "iat" => DateTime.to_unix(issued_at, :millisecond),
                          "exp" => DateTime.to_unix(expiration_time, :millisecond)
                        },
                        secret: secret
                      )

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

            {:error, reason} ->
              {:error, reason}
          end

        {:captcha_required, payload} ->
          {:ok, payload}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def consume(params, opts \\ []) do
    params =
      params
      |> normalize()
      |> put_audience_from_opts(opts)

    now = Keyword.get(opts, :now, DateTime.utc_now())

    case Keyword.get(opts, :nonce_token) do
      nil ->
        store =
          Keyword.get_lazy(opts, :store, fn -> Application.fetch_env!(:siwa, :nonce_store) end)

        with :ok <- ensure_audience(Map.get(params, :audience)),
             {:ok, stored} <- consume_nonce(store, params),
             :ok <- validate_entry(stored, params, now) do
          {:ok, stored}
        end

      token ->
        nonce_secret =
          Keyword.get_lazy(opts, :nonce_secret, fn ->
            Keyword.fetch!(opts, :secret)
          end)

        with :ok <- ensure_audience(Map.get(params, :audience)),
             {:ok, stored} <- verify_nonce_token(token, nonce_secret: nonce_secret, now: now),
             :ok <- validate_token_entry(stored, params),
             :ok <- consume_nonce_token_once(token, stored) do
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
        Keyword.get_lazy(opts, :secret, fn -> Application.fetch_env!(:siwa, :nonce_secret) end)
      end)

    body = Jason.encode!(payload)
    encoded_body = Base.url_encode64(body, padding: false)
    mac = :crypto.mac(:hmac, :sha256, secret, encoded_body) |> Base.url_encode64(padding: false)
    {:ok, encoded_body <> "." <> mac}
  end

  def verify_nonce_token(token, opts \\ [])

  def verify_nonce_token(token, opts) when is_binary(token) do
    secret =
      Keyword.get_lazy(opts, :nonce_secret, fn ->
        Keyword.get_lazy(opts, :secret, fn -> Application.fetch_env!(:siwa, :nonce_secret) end)
      end)

    now_ms =
      opts
      |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end)
      |> DateTime.to_unix(:millisecond)

    with {:ok, encoded_body, mac} <- split_nonce_token(token),
         :ok <- verify_nonce_token_mac(encoded_body, mac, secret),
         {:ok, payload} <- decode_nonce_token_payload(encoded_body),
         :ok <- check_nonce_token_expiration(payload, now_ms) do
      {:ok, payload}
    end
  end

  def verify_nonce_token(_token, _opts), do: {:error, :invalid_nonce_token}

  defp split_nonce_token(token) do
    case String.split(token, ".") do
      [encoded_body, mac] when encoded_body != "" and mac != "" -> {:ok, encoded_body, mac}
      _ -> {:error, :invalid_nonce_token}
    end
  end

  defp verify_nonce_token_mac(encoded_body, mac, secret) do
    expected =
      :crypto.mac(:hmac, :sha256, secret, encoded_body) |> Base.url_encode64(padding: false)

    if Plug.Crypto.secure_compare(expected, mac) do
      :ok
    else
      {:error, :invalid_nonce_token}
    end
  end

  defp decode_nonce_token_payload(encoded_body) do
    with {:ok, body} <- Base.url_decode64(encoded_body, padding: false),
         {:ok, payload} when is_map(payload) <- Jason.decode(body) do
      {:ok, payload}
    else
      _ -> {:error, :invalid_nonce_token}
    end
  end

  defp check_nonce_token_expiration(payload, now_ms) do
    case payload do
      %{"exp" => exp} when is_integer(exp) and exp >= now_ms -> :ok
      _ -> {:error, :invalid_nonce_token}
    end
  end

  defp ensure_registry(agent_registry) do
    case Registry.parse_agent_registry(agent_registry) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp ensure_audience(audience) when is_binary(audience) do
    if String.trim(audience) == "", do: {:error, :audience_required}, else: :ok
  end

  defp ensure_audience(_audience), do: {:error, :audience_required}

  defp maybe_handle_captcha(params, opts, now) do
    response = Map.get(params, :challenge_response)

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
                 {:ok, verified} <-
                   Captcha.verify_challenge(token, unpacked.solution, secret,
                     timing_tolerance_seconds: 2
                   ),
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

    captcha_secret =
      Keyword.get_lazy(opts, :captcha_secret, fn ->
        Application.fetch_env!(:siwa, :nonce_secret)
      end)

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
        case policy.(%{
               address: params.address,
               agent_id: params.agent_id,
               agent_registry: params.agent_registry
             }) do
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
        case module.challenge(
               %{
                 address: params.address,
                 agent_id: params.agent_id,
                 agent_registry: params.agent_registry
               },
               opts
             ) do
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

  defp store_nonce(fun, params, nonce, metadata) when is_function(fun, 4),
    do: fun.(key(params), nonce, metadata, params)

  defp consume_nonce(store, params) when is_atom(store) do
    store.consume(key(params), params.nonce)
  end

  defp consume_nonce(fun, params) when is_function(fun, 2), do: fun.(key(params), params.nonce)

  defp validate_entry(entry, params, now) do
    now_ms = DateTime.to_unix(now, :millisecond)
    exp_ms = entry.expiration_time |> DateTime.to_unix(:millisecond)

    cond do
      String.downcase(entry.address) != String.downcase(params.address) ->
        {:error, :nonce_address_mismatch}

      entry.agent_id != params.agent_id ->
        {:error, :nonce_agent_id_mismatch}

      entry.agent_registry != params.agent_registry ->
        {:error, :nonce_registry_mismatch}

      entry.audience != params.audience ->
        {:error, :nonce_audience_mismatch}

      now_ms > exp_ms ->
        {:error, :nonce_expired}

      true ->
        :ok
    end
  end

  defp validate_token_entry(entry, params) do
    cond do
      String.downcase(entry["address"]) != String.downcase(params.address) ->
        {:error, :nonce_address_mismatch}

      entry["agent_id"] != params.agent_id ->
        {:error, :nonce_agent_id_mismatch}

      entry["agent_registry"] != params.agent_registry ->
        {:error, :nonce_registry_mismatch}

      entry["audience"] != params.audience ->
        {:error, :nonce_audience_mismatch}

      entry["nonce"] != params.nonce ->
        {:error, :nonce_mismatch}

      true ->
        :ok
    end
  end

  defp key(params),
    do:
      Enum.join(
        [
          String.downcase(params.address),
          params.agent_id,
          String.downcase(params.agent_registry),
          params.audience
        ],
        ":"
      )

  defp consume_nonce_token_once(token, stored) do
    token_key = :crypto.hash(:sha256, token)
    Siwa.Nonce.TokenReplayStore.consume(token_key, stored["exp"])
  end

  defp normalize(params) when is_map(params),
    do: Map.new(params, fn {k, v} -> {normalize_key(k), v} end)

  defp normalize(params) when is_list(params), do: params |> Enum.into(%{}) |> normalize()

  defp put_audience_from_opts(params, opts) do
    case {Map.get(params, :audience), Keyword.get(opts, :audience)} do
      {nil, audience} when is_binary(audience) -> Map.put(params, :audience, audience)
      _ -> params
    end
  end

  defp normalize_key("agent_id"), do: :agent_id
  defp normalize_key("agent_registry"), do: :agent_registry
  defp normalize_key("audience"), do: :audience
  defp normalize_key("challenge_response"), do: :challenge_response
  defp normalize_key("address"), do: :address
  defp normalize_key("nonce"), do: :nonce
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: key
end

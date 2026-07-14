defmodule RegentChatGPT.OAuth do
  @moduledoc "OAuth helpers for ChatGPT account connection flows."

  alias RegentChatGPT.{Config, Error, HTTP, JWT, TokenSet}

  @dead_refresh_errors MapSet.new([
                         "refresh_token_expired",
                         "refresh_token_reused",
                         "refresh_token_invalidated",
                         "invalid_grant"
                       ])

  @spec authorization_url(Config.t() | keyword() | map(), keyword()) :: String.t()
  def authorization_url(config, params) do
    config = Config.resolve(config)
    pkce = Keyword.fetch!(params, :pkce)

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => config.client_id,
        "redirect_uri" => Keyword.fetch!(params, :redirect_uri),
        "scope" => config.scope,
        "code_challenge" => Map.fetch!(pkce, :challenge),
        "code_challenge_method" => "S256",
        "state" => Keyword.fetch!(params, :state),
        "id_token_add_organizations" => "true",
        "codex_cli_simplified_flow" => "true",
        "originator" => config.originator
      })

    config.authorize_url
    |> URI.parse()
    |> Map.put(:query, query)
    |> URI.to_string()
  end

  @spec exchange_authorization_code(Config.t() | keyword() | map(), keyword()) ::
          {:ok, TokenSet.t()} | {:error, Error.t()}
  def exchange_authorization_code(config, params) do
    config = Config.resolve(config)

    body =
      URI.encode_query(%{
        "grant_type" => "authorization_code",
        "client_id" => config.client_id,
        "code" => Keyword.fetch!(params, :code),
        "code_verifier" => Keyword.fetch!(params, :code_verifier),
        "redirect_uri" => Keyword.fetch!(params, :redirect_uri)
      })

    request_token(config, :token_exchange_failed,
      method: :post,
      url: config.token_url,
      headers: [
        {"content-type", "application/x-www-form-urlencoded"},
        {"accept", "application/json"}
      ],
      body: body
    )
  end

  @spec refresh_tokens(Config.t() | keyword() | map(), String.t()) ::
          {:ok, TokenSet.t()} | {:error, Error.t()}
  def refresh_tokens(config, refresh_token) when is_binary(refresh_token) do
    config = Config.resolve(config)

    body =
      Jason.encode!(%{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_token,
        "client_id" => config.client_id,
        "scope" => config.scope
      })

    with {:ok, response} <-
           HTTP.request(config,
             method: :post,
             url: config.token_url,
             headers: [{"content-type", "application/json"}, {"accept", "application/json"}],
             body: body
           ),
         {:ok, raw} <- decode_json(response) do
      if ok_status?(response) do
        to_tokens(raw, previous_refresh_token: refresh_token)
      else
        error_code = raw_error(raw)

        if MapSet.member?(@dead_refresh_errors, error_code) do
          {:error,
           Error.new(
             :refresh_token_invalid,
             "Refresh token is no longer valid. The user must connect ChatGPT again.",
             status: response.status,
             body: response_body(response)
           )}
        else
          {:error,
           Error.new(:token_refresh_failed, "Token refresh failed.",
             status: response.status,
             body: response_body(response)
           )}
        end
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         Error.new(:network_error, "Failed to reach the token endpoint.", body: inspect(reason))}
    end
  end

  @doc false
  @spec to_tokens(map(), keyword()) :: {:ok, TokenSet.t()} | {:error, Error.t()}
  def to_tokens(raw, opts \\ []) when is_map(raw) do
    access_token = raw["access_token"] || raw[:access_token]

    if is_binary(access_token) and access_token != "" do
      id_token = raw["id_token"] || raw[:id_token]
      expires_in = parse_int(raw["expires_in"] || raw[:expires_in])
      now = Keyword.get(opts, :now, System.system_time(:millisecond))

      {:ok,
       %TokenSet{
         access_token: access_token,
         refresh_token:
           raw["refresh_token"] || raw[:refresh_token] ||
             Keyword.get(opts, :previous_refresh_token),
         id_token: id_token,
         account_id: JWT.derive_account_id(id_token) || JWT.derive_account_id(access_token),
         expires_at:
           if(is_integer(expires_in),
             do: now + expires_in * 1000,
             else: JWT.token_expiry(access_token)
           )
       }}
    else
      {:error, Error.new(:token_exchange_failed, "Token response missing access_token.")}
    end
  end

  defp request_token(config, error_code, opts) do
    with {:ok, response} <- HTTP.request(config, opts),
         {:ok, raw} <- decode_json(response) do
      if ok_status?(response) do
        to_tokens(raw)
      else
        {:error,
         Error.new(error_code, "Authorization code exchange failed.",
           status: response.status,
           body: response_body(response)
         )}
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         Error.new(:network_error, "Failed to reach the token endpoint.", body: inspect(reason))}
    end
  end

  defp decode_json(%{body: body}) when is_map(body), do: {:ok, stringify_keys(body)}

  defp decode_json(%{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:error, Error.new(:token_exchange_failed, "Token endpoint returned invalid JSON.")}
    end
  end

  defp decode_json(_response), do: {:ok, %{}}

  defp ok_status?(%{status: status}) when is_integer(status), do: status >= 200 and status < 300

  defp response_body(%{body: body}) when is_binary(body), do: body
  defp response_body(%{body: body}), do: inspect(body)
  defp response_body(_response), do: nil

  defp raw_error(%{"error" => error}) when is_binary(error), do: error
  defp raw_error(_raw), do: nil

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      entry -> entry
    end)
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil
end

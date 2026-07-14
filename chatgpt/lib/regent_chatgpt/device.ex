defmodule RegentChatGPT.Device do
  @moduledoc "ChatGPT device-code authorization flow."

  alias RegentChatGPT.{Config, DeviceCode, Error, HTTP, OAuth}

  @device_code_ttl_ms 15 * 60 * 1000

  @spec request_device_code(Config.t() | keyword() | map(), keyword()) ::
          {:ok, DeviceCode.t()} | {:error, Error.t()}
  def request_device_code(config, opts \\ []) do
    config = Config.resolve(config)
    now = Keyword.get(opts, :now, fn -> System.system_time(:millisecond) end)

    with {:ok, response} <-
           HTTP.request(config,
             method: :post,
             url: "#{config.device_api_base}/deviceauth/usercode",
             headers: [{"content-type", "application/json"}, {"accept", "application/json"}],
             body: Jason.encode!(%{"client_id" => config.client_id})
           ) do
      cond do
        response.status == 404 ->
          {:error,
           Error.new(
             :device_code_disabled,
             "Device-code login is not enabled for this issuer.",
             status: 404,
             body: response_body(response)
           )}

        not ok_status?(response) ->
          {:error,
           Error.new(:device_code_request_failed, "Device code request failed.",
             status: response.status,
             body: response_body(response)
           )}

        true ->
          case decode_json(response, :device_code_request_failed) do
            {:ok, raw} -> to_device_code(raw, config, now.())
            {:error, error} -> {:error, error}
          end
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         Error.new(:network_error, "Failed to reach the device authorization endpoint.",
           body: inspect(reason)
         )}
    end
  end

  @spec poll_device_code(Config.t() | keyword() | map(), DeviceCode.t() | map()) ::
          {:ok, %{status: :pending | :authorized}} | {:error, Error.t()}
  def poll_device_code(config, device) do
    config = Config.resolve(config)

    with {:ok, response} <-
           HTTP.request(config,
             method: :post,
             url: "#{config.device_api_base}/deviceauth/token",
             headers: [{"content-type", "application/json"}, {"accept", "application/json"}],
             body:
               Jason.encode!(%{
                 "device_auth_id" => device_value(device, :device_auth_id),
                 "user_code" => device_value(device, :user_code)
               })
           ) do
      cond do
        response.status in [403, 404, 429] ->
          {:ok, %{status: :pending}}

        not ok_status?(response) ->
          {:error,
           Error.new(:token_exchange_failed, "Device authorization failed.",
             status: response.status,
             body: response_body(response)
           )}

        true ->
          case decode_json(response, :token_exchange_failed) do
            {:ok, raw} -> to_poll_result(raw)
            {:error, error} -> {:error, error}
          end
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         Error.new(:network_error, "Failed to reach the device token endpoint.",
           body: inspect(reason)
         )}
    end
  end

  @spec exchange_device_authorization(Config.t() | keyword() | map(), map()) ::
          {:ok, RegentChatGPT.TokenSet.t()} | {:error, Error.t()}
  def exchange_device_authorization(config, %{status: :authorized} = poll) do
    config = Config.resolve(config)

    OAuth.exchange_authorization_code(config,
      code: poll.authorization_code,
      code_verifier: poll.code_verifier,
      redirect_uri: config.device_redirect_uri
    )
  end

  defp to_device_code(raw, config, now_ms) do
    user_code = raw["user_code"] || raw["usercode"]

    if is_binary(raw["device_auth_id"]) and is_binary(user_code) do
      {:ok,
       %DeviceCode{
         device_auth_id: raw["device_auth_id"],
         user_code: user_code,
         verification_url: config.device_verification_url,
         interval: normalize_interval(raw["interval"]),
         expires_at: now_ms + @device_code_ttl_ms
       }}
    else
      {:error,
       Error.new(:device_code_request_failed, "Device code response was missing required fields.")}
    end
  end

  defp to_poll_result(%{
         "authorization_code" => authorization_code,
         "code_challenge" => code_challenge,
         "code_verifier" => code_verifier
       })
       when is_binary(authorization_code) and is_binary(code_challenge) and
              is_binary(code_verifier) do
    {:ok,
     %{
       status: :authorized,
       authorization_code: authorization_code,
       code_challenge: code_challenge,
       code_verifier: code_verifier
     }}
  end

  defp to_poll_result(_raw), do: {:ok, %{status: :pending}}

  defp decode_json(%{body: body}, _code) when is_map(body), do: {:ok, stringify_keys(body)}

  defp decode_json(%{body: body}, code) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:error, Error.new(code, "Endpoint returned invalid JSON.")}
    end
  end

  defp decode_json(_response, _code), do: {:ok, %{}}

  defp ok_status?(%{status: status}) when is_integer(status), do: status >= 200 and status < 300

  defp response_body(%{body: body}) when is_binary(body), do: body
  defp response_body(%{body: body}), do: inspect(body)
  defp response_body(_response), do: nil

  defp normalize_interval(value) when is_integer(value) and value > 0, do: value

  defp normalize_interval(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _rest} when int > 0 -> int
      _ -> 5
    end
  end

  defp normalize_interval(_value), do: 5

  defp device_value(%DeviceCode{} = device, key), do: Map.fetch!(device, key)

  defp device_value(device, key) when is_map(device),
    do: Map.get(device, key) || Map.get(device, Atom.to_string(key))

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      entry -> entry
    end)
  end
end

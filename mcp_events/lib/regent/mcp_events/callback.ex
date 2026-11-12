defmodule Regent.MCPEvents.Callback do
  @moduledoc """
  HTTPS callbacks through `RegentHttp.Public`: every DNS answer is checked public
  and the connection goes to the checked address, while the original hostname
  remains the HTTP Host, TLS SNI and certificate verification name. Each call
  opens a new connection; there are no proxies, redirects, pools or hidden retries.
  """

  @timeout_ms 10_000
  @response_limit 16_384

  @doc "Checks callback URL syntax, including non-public literal addresses."
  def validate(url) do
    case RegentHttp.Public.uri(url) do
      {:ok, uri} -> {:ok, uri}
      {:error, _} -> {:error, :invalid_callback}
    end
  end

  @doc "Posts exact signed bytes with a total bounded network deadline."
  def post(url, body, headers), do: do_post(url, body, headers, :body)

  @doc "Posts one event; a complete HTTP response header acknowledges receipt without waiting for a body."
  def post_event(url, body, headers), do: do_post(url, body, headers, :headers)

  defp do_post(url, body, headers, answer) when is_binary(body) and byte_size(body) <= 262_144 do
    with {:ok, _uri} <- validate(url) do
      case RegentHttp.Public.request(:post, url,
             body: body,
             headers: headers,
             answer: answer,
             max_bytes: @response_limit,
             timeout: @timeout_ms
           ) do
        {:ok, %{status: status, body: response}} -> {:ok, %{status: status, body: response}}
        {:error, :too_large} -> {:error, :response_too_large}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp do_post(_, _, _, _), do: {:error, :payload_too_large}
end

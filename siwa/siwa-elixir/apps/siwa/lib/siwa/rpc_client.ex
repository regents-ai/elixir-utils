defmodule Siwa.RPCClient do
  @moduledoc false

  alias Req.TransportError

  @default_timeout_ms 5_000

  @type error ::
          :rpc_url_required
          | :rpc_request_failed
          | :rpc_request_timed_out
          | :invalid_rpc_response
          | {:rpc_error, term()}

  @spec call(String.t(), String.t(), list(), keyword()) :: {:ok, term()} | {:error, error()}
  def call(url, method, params, opts \\ [])

  def call(url, method, params, opts)
      when is_binary(url) and is_binary(method) and is_list(params) do
    with {:ok, url} <- normalize_url(url) do
      timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

      opts
      |> request_options(url, method, params, timeout_ms)
      |> Req.new()
      |> Req.post()
      |> parse_response()
    end
  end

  def call(_url, _method, _params, _opts), do: {:error, :rpc_request_failed}

  defp normalize_url(url) do
    case String.trim(url) do
      "" -> {:error, :rpc_url_required}
      trimmed -> {:ok, trimmed}
    end
  end

  defp request_options(opts, url, method, params, timeout_ms) do
    request_opts = [
      url: url,
      receive_timeout: timeout_ms,
      retry: false,
      json: %{
        id: 1,
        jsonrpc: "2.0",
        method: method,
        params: params
      }
    ]

    case Keyword.get(opts, :finch) do
      nil -> Keyword.put(request_opts, :connect_options, timeout: timeout_ms)
      finch -> Keyword.put(request_opts, :finch, finch)
    end
  end

  defp parse_response({:ok, %{status: status, body: body}}) when status in 200..299,
    do: parse_rpc_body(body)

  defp parse_response({:ok, %{status: _status}}), do: {:error, :rpc_request_failed}

  defp parse_response({:error, %TransportError{reason: :timeout}}),
    do: {:error, :rpc_request_timed_out}

  defp parse_response({:error, error}), do: {:error, map_transport_error(error)}

  defp parse_rpc_body(%{"error" => %{"message" => message}})
       when is_binary(message) and byte_size(message) > 0,
       do: {:error, {:rpc_error, message}}

  defp parse_rpc_body(%{"error" => error}), do: {:error, {:rpc_error, error}}
  defp parse_rpc_body(%{"result" => result}), do: {:ok, result}
  defp parse_rpc_body(_body), do: {:error, :invalid_rpc_response}

  defp map_transport_error(error) do
    message = Exception.message(error)

    if String.contains?(String.downcase(message), "timeout") do
      :rpc_request_timed_out
    else
      :rpc_request_failed
    end
  end
end

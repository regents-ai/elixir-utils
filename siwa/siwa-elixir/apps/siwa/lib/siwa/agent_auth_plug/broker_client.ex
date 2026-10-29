defmodule Siwa.AgentAuthPlug.BrokerClient do
  @moduledoc """
  HTTP transport for the shared SIWA broker `http-verify` endpoint.

  The HTTP call is performed by the `:http` module, which must expose
  `request(keyword())` with Req-style options and return
  `{:ok, %{status: integer(), body: term()}} | {:error, term()}` (for
  Regent apps this is `RegentHttp`).

  Options:

    * `:http` — HTTP module as described above (required)
    * `:base_url` — broker base URL; a trailing `/` is trimmed (required)
    * `:audience` — value for the `x-siwa-audience` header (required)
    * `:connect_timeout_ms` — optional connect timeout
    * `:receive_timeout_ms` — optional receive timeout

  When the timeouts are omitted the `:http` module's defaults apply.
  """

  @behaviour Siwa.AgentAuthPlug.Client

  @impl true
  def verify_http_request(payload, opts) when is_map(payload) do
    http = Keyword.fetch!(opts, :http)
    base_url = opts |> Keyword.fetch!(:base_url) |> String.trim_trailing("/")

    request_opts =
      [
        method: :post,
        url: base_url <> Siwa.AgentAuthPlug.http_verify_path(),
        json: payload,
        headers: [{"x-siwa-audience", Keyword.fetch!(opts, :audience)}]
      ]
      |> put_connect_timeout(Keyword.get(opts, :connect_timeout_ms))
      |> put_receive_timeout(Keyword.get(opts, :receive_timeout_ms))

    case http.request(request_opts) do
      {:ok, %{status: status, body: body}} -> {:ok, %{status: status, body: body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_connect_timeout(request_opts, nil), do: request_opts

  defp put_connect_timeout(request_opts, timeout_ms) when is_integer(timeout_ms),
    do: Keyword.put(request_opts, :connect_options, timeout: timeout_ms)

  defp put_receive_timeout(request_opts, nil), do: request_opts

  defp put_receive_timeout(request_opts, timeout_ms) when is_integer(timeout_ms),
    do: Keyword.put(request_opts, :receive_timeout, timeout_ms)
end

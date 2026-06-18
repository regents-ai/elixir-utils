defmodule Siwa.AgentAuthPlug do
  @moduledoc """
  Shared agent-auth plug for Regent Phoenix apps backed by the SIWA broker.

  The plug downcases the request headers, builds the canonical
  `POST /api/shared/siwa/http-verify` payload, sends it through the
  app-provided client, and hands every app-specific decision to the app's
  hooks module:

    * `c:Siwa.AgentAuthPlug.Hooks.before_verify/2` runs before the broker
      call and can pre-validate the request (for example required `x-agent-*`
      headers), returning context for `accept/3`.
    * `c:Siwa.AgentAuthPlug.Hooks.accept/3` runs on a verified envelope and
      performs claims handling, persistence, and assigns.
    * `c:Siwa.AgentAuthPlug.Hooks.deny/2` renders the app's deny response
      (and emits app telemetry) for any failure.

  Options (resolved at call time by the app plug):

    * `:client` — module implementing `Siwa.AgentAuthPlug.Client` (required)
    * `:hooks` — module implementing `Siwa.AgentAuthPlug.Hooks` (required)
    * `:audience` — SIWA audience string passed to the client (required)
    * `:signed_path` — `:path_and_query` (default) or `:path_only`
    * `:body` — `:if_present` (default: omit the payload `"body"` when no raw
      body was captured) or `:always` (send the captured raw body or `""`)

  Deny metadata is a map with `:reason` and `:source` plus optional detail
  keys (`:siwa_status`, `:siwa_code`, `:transport_error`, `:missing_headers`,
  `:invalid_header`).
  """

  @behaviour Plug

  defmodule Client do
    @moduledoc """
    Transport for the shared SIWA broker `http-verify` call.

    `verify_http_request/2` receives the canonical payload map and
    `audience:` in `opts`. It returns the broker response as
    `{:ok, %{status: integer(), body: term()}}`, or `{:error, deny_meta}`
    (a map with `:reason`/`:source`) for configuration failures, or
    `{:error, term()}` for transport failures.
    """

    @callback verify_http_request(payload :: map(), opts :: keyword()) ::
                {:ok, %{status: integer(), body: term()}} | {:error, term()}
  end

  defmodule Hooks do
    @moduledoc """
    App-specific hooks for `Siwa.AgentAuthPlug`.
    """

    @callback before_verify(conn :: Plug.Conn.t(), headers :: %{String.t() => String.t()}) ::
                {:ok, context :: term()} | {:error, deny_meta :: map()}

    @callback accept(conn :: Plug.Conn.t(), data :: map(), context :: term()) ::
                {:ok, Plug.Conn.t()} | {:error, deny_meta :: map()}

    @callback deny(conn :: Plug.Conn.t(), deny_meta :: map()) :: Plug.Conn.t()
  end

  @http_verify_path "/api/shared/siwa/http-verify"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    hooks = Keyword.fetch!(opts, :hooks)
    headers = downcase_headers(conn.req_headers)

    with {:ok, context} <- hooks.before_verify(conn, headers),
         {:ok, data} <- verify_envelope(conn, headers, opts),
         {:ok, conn} <- hooks.accept(conn, data, context) do
      conn
    else
      {:error, deny_meta} when is_map(deny_meta) -> hooks.deny(conn, deny_meta)
    end
  end

  @doc "Path of the broker verification endpoint."
  @spec http_verify_path() :: String.t()
  def http_verify_path, do: @http_verify_path

  defp verify_envelope(conn, headers, opts) do
    client = Keyword.fetch!(opts, :client)
    payload = http_verify_payload(conn, headers, opts)

    case client.verify_http_request(payload, audience: Keyword.fetch!(opts, :audience)) do
      {:ok,
       %{
         status: 200,
         body: %{"code" => "http_envelope_valid", "data" => data}
       }}
      when is_map(data) ->
        {:ok, data}

      {:ok, %{status: status, body: body}} when is_integer(status) ->
        {:error, status_deny_meta(status, body)}

      {:error, deny_meta} when is_non_struct_map(deny_meta) ->
        {:error, deny_meta}

      {:error, reason} ->
        {:error,
         %{
           reason: :siwa_request_failed,
           source: :siwa_http,
           transport_error: normalize_transport_error(reason)
         }}
    end
  end

  defp http_verify_payload(conn, headers, opts) do
    payload = %{
      "method" => conn.method,
      "path" => signed_path(conn, Keyword.get(opts, :signed_path, :path_and_query)),
      "headers" => headers
    }

    case {Keyword.get(opts, :body, :if_present), conn.assigns[:raw_body]} do
      {_mode, body} when is_binary(body) -> Map.put(payload, "body", body)
      {:always, _missing} -> Map.put(payload, "body", "")
      {:if_present, _missing} -> payload
    end
  end

  defp signed_path(%Plug.Conn{request_path: path}, :path_only), do: path
  defp signed_path(%Plug.Conn{request_path: path, query_string: ""}, :path_and_query), do: path

  defp signed_path(%Plug.Conn{request_path: path, query_string: query}, :path_and_query),
    do: path <> "?" <> query

  defp downcase_headers(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)
  end

  defp status_deny_meta(status, body) do
    metadata = %{reason: :"siwa_http_#{status}", source: :siwa_http, siwa_status: status}

    case body do
      %{"error" => %{"code" => code}} when is_binary(code) and code != "" ->
        Map.put(metadata, :siwa_code, code)

      _body ->
        metadata
    end
  end

  defp normalize_transport_error(error) do
    case error do
      reason when is_atom(reason) -> reason
      %{reason: reason} when is_atom(reason) -> reason
      _other -> :unknown_transport_error
    end
  end
end

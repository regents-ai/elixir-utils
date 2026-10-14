defmodule Siwa.AgentAuthPlug do
  @moduledoc """
  Shared agent-auth plug for Regent Phoenix apps backed by the SIWA broker.

  Before any hook runs, the plug refuses, with `source: :siwa_plug`:

    * `:duplicate_proof` — a signed header (`Siwa.Contract.forwarded_headers/0`)
      sent more than once;
    * `:unsupported_query` — a query string, unless the site signs queries
      (`query: :signed`);
    * `:missing_signed_body` — a body whose exact bytes `read_body/3` did not
      capture whole, so the signature would not cover what the site reads.

  It then builds the canonical `POST /api/shared/siwa/http-verify` payload
  carrying only the signed headers and, for a request with a body, that body's
  digest (`Siwa.content_digest_for_body/1`) from the bytes this site read. The
  body itself never leaves the site. It sends the payload through the
  app-provided client,
  and hands every app-specific decision to the app's hooks module:

    * `c:Siwa.AgentAuthPlug.Hooks.before_verify/2` runs before the broker
      call and can pre-validate the request (for example required `x-agent-*`
      headers), returning context for `accept/3`.
    * `c:Siwa.AgentAuthPlug.Hooks.accept/3` runs on a verified envelope and
      performs claims handling, persistence, and assigns.
    * `c:Siwa.AgentAuthPlug.Hooks.deny/2` renders the app's deny response
      (and emits app telemetry) for any failure.

  A service refusal (status 400..599) reaches `deny/2` as `:"siwa_http_<status>"`
  with the service's `:siwa_status`, `:siwa_code`, `:siwa_message` and
  `:siwa_hint`. Any other answer without a verdict, and a failed request, reach it
  as `:siwa_request_failed`.

  Options (resolved at call time by the app plug):

    * `:client` — module implementing `Siwa.AgentAuthPlug.Client` (required)
    * `:hooks` — module implementing `Siwa.AgentAuthPlug.Hooks` (required)
    * `:audience` — SIWA audience string passed to the client (required)
    * `:query` — `:refuse` (default) or `:signed` (the query string is part of
      the signed path)
    * `:body` — `:if_present` (default: omit the payload `"body_digest"` when
      no raw body was captured) or `:always` (send the digest of the captured
      raw body, or of `""`)
    * `:read_only` — `true` only on a route or tool that changes nothing and
      spends nothing (default `false`). Such a request may be checked on a lease,
      described below; every other request goes to the sign-in server.

  ## Leases, for requests that read

  A request with `read_only: true` asks the sign-in server for a lease
  (`"lease": true` in the payload). For an agent that signs with its own key,
  the server answers with `leaseExpiresAt`: about ten minutes, never past the
  receipt's expiry. Until then, a read-only request under the same receipt at
  the same audience is checked on this node instead
  (`Siwa.RequestAuth.verify_leased_request/3`): every check the server makes
  except the receipt's secret, against the claims it read, with single use kept
  in `Siwa.RequestAuth.ReplayStore`. A smart wallet is never given a lease.

  `accept/3` runs on every request, leased or not, with the answer the sign-in
  server gave when the lease began. Leases are held in memory
  (`Siwa.AgentAuthPlug.Leases`), so a restart ends them all.

  A refusal made on a lease reaches `deny/2` in the same shape as the sign-in
  server's (`:"siwa_http_<status>"`, `:siwa_status`, `:siwa_code` and
  `:siwa_message` from `Siwa.Contract.refusal/1`), with `source: :siwa_lease`
  and no `:siwa_hint`: the site's own hint is the one shown.

  A site's body reader passes each signed route's body to `read_body/3`. Deny
  metadata is a map with `:reason` and `:source` plus optional detail keys (`:siwa_status`, `:siwa_code`,
  `:siwa_message`, `:siwa_hint`, `:transport_error`, `:missing_headers`,
  `:invalid_header`).
  """

  @behaviour Plug

  alias Siwa.AgentAuthPlug.Leases
  alias Siwa.Contract

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

    with :ok <- refuse_repeats(conn),
         :ok <- refuse_query(conn, Keyword.get(opts, :query, Contract.query_default())),
         :ok <- refuse_unsigned_body(conn),
         {:ok, context} <- hooks.before_verify(conn, headers),
         {:ok, data} <- verify(conn, headers, opts),
         {:ok, conn} <- hooks.accept(conn, data, context) do
      conn
    else
      {:error, deny_meta} when is_map(deny_meta) -> hooks.deny(conn, deny_meta)
    end
  end

  @doc "Path of the broker verification endpoint."
  @spec http_verify_path() :: String.t()
  def http_verify_path, do: @http_verify_path

  @doc "Whether the request carries any signed agent header, telling an agent's request from a person's."
  @spec signed_request?(Plug.Conn.t()) :: boolean()
  def signed_request?(conn) do
    forwarded = Contract.forwarded_headers()
    Enum.any?(conn.req_headers, fn {name, _value} -> String.downcase(name) in forwarded end)
  end

  # The map of headers keeps one value per name, so repeats are found on the
  # request's own list.
  defp refuse_repeats(conn) do
    names = Enum.map(conn.req_headers, fn {name, _value} -> String.downcase(name) end)
    repeats = names -- Enum.uniq(names)

    if Enum.any?(repeats, &(&1 in Contract.forwarded_headers())),
      do: {:error, %{reason: :duplicate_proof, source: :siwa_plug}},
      else: :ok
  end

  defp refuse_query(%Plug.Conn{query_string: ""}, _query), do: :ok
  defp refuse_query(_conn, :signed), do: :ok

  defp refuse_query(_conn, :refuse),
    do: {:error, %{reason: :unsupported_query, source: :siwa_plug}}

  @doc """
  A `Plug.Parsers` body reader for a signed route, called as
  `read_body(conn, opts, limit)` from the site's own reader. It keeps the exact
  bytes in `conn.assigns.raw_body`, marks whether they are the whole body, and
  refuses a body over `limit` bytes.
  """
  @spec read_body(Plug.Conn.t(), keyword(), pos_integer()) ::
          {:ok | :more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts, limit) do
    opts = opts |> Keyword.put(:length, limit) |> Keyword.put(:read_length, limit + 1)

    case Plug.Conn.read_body(conn, opts) do
      {status, chunk, conn} when status in [:ok, :more] ->
        body = Map.get(conn.assigns, :raw_body, "") <> chunk
        if byte_size(body) > limit, do: raise(Plug.Parsers.RequestTooLargeError)

        conn =
          conn
          |> Plug.Conn.assign(:raw_body, body)
          |> Plug.Conn.put_private(:siwa_body_complete, status == :ok)

        {status, chunk, conn}

      other ->
        other
    end
  end

  defp refuse_unsigned_body(conn) do
    if body_sent?(conn) and not body_captured?(conn),
      do: {:error, %{reason: :missing_signed_body, source: :siwa_plug}},
      else: :ok
  end

  defp body_captured?(%Plug.Conn{
         assigns: %{raw_body: body},
         private: %{siwa_body_complete: true}
       })
       when is_binary(body),
       do: true

  defp body_captured?(_conn), do: false

  defp body_sent?(conn) do
    Map.has_key?(conn.assigns, :raw_body) or
      Plug.Conn.get_req_header(conn, "content-length") not in [[], ["0"]] or
      Plug.Conn.get_req_header(conn, "transfer-encoding") != [] or
      conn.body_params not in [%{}, %Plug.Conn.Unfetched{aspect: :body_params}]
  end

  defp verify(conn, headers, opts) do
    if Keyword.get(opts, :read_only, false),
      do: verify_read(conn, headers, opts),
      else: verify_envelope(conn, headers, opts, %{})
  end

  defp verify_read(conn, headers, opts) do
    audience = Keyword.fetch!(opts, :audience)
    receipt = Map.get(headers, Contract.header_for("receipt"))
    now = DateTime.utc_now()

    case Leases.fetch(audience, receipt, DateTime.to_unix(now, :millisecond)) do
      {:ok, lease} ->
        check_on_lease(conn, headers, lease, now, opts)

      :none ->
        with {:ok, data} <- verify_envelope(conn, headers, opts, %{"lease" => true}) do
          begin_lease(conn, headers, receipt, data, now, opts)
        end
    end
  end

  # The sign-in server has verified this request. With a lease, the request is
  # also recorded here as used, so it cannot be served again on the lease.
  defp begin_lease(
         conn,
         headers,
         receipt,
         %{"leaseExpiresAt" => lease_expires_at} = data,
         now,
         opts
       ) do
    with {:ok, lease} <- lease(receipt, data, lease_expires_at) do
      :ok = Leases.keep(Keyword.fetch!(opts, :audience), lease)
      check_on_lease(conn, headers, lease, now, opts)
    end
  end

  defp begin_lease(_conn, _headers, _receipt, data, _now, _opts), do: {:ok, data}

  defp lease(receipt, data, lease_expires_at) do
    with %{
           "walletAddress" => wallet,
           "keyId" => key_id,
           "chainId" => chain_id,
           "receiptExpiresAt" => receipt_expires_at,
           "principal" => %{"audience" => audience}
         } <- data,
         {:ok, lease_ends, _offset} <- DateTime.from_iso8601(lease_expires_at),
         {:ok, receipt_ends, _offset} <- DateTime.from_iso8601(receipt_expires_at) do
      {:ok,
       %{
         receipt: receipt,
         claims: %{"sub" => wallet, "key_id" => key_id, "chain_id" => chain_id, "aud" => audience},
         until_ms:
           min(
             DateTime.to_unix(lease_ends, :millisecond),
             DateTime.to_unix(receipt_ends, :millisecond)
           ),
         data: data
       }}
    else
      _unreadable -> {:error, %{reason: :siwa_request_failed, source: :siwa_http}}
    end
  end

  defp check_on_lease(conn, headers, lease, now, opts) do
    request = http_verify_payload(conn, headers, opts)

    case Siwa.RequestAuth.verify_leased_request(request, lease,
           audience: Keyword.fetch!(opts, :audience),
           now: now
         ) do
      {:ok, _verified} -> {:ok, lease.data}
      {:error, reason} -> {:error, lease_deny_meta(reason)}
    end
  end

  defp lease_deny_meta(reason) do
    {status, code, message} = Contract.refusal(reason)

    %{
      reason: :"siwa_http_#{status}",
      source: :siwa_lease,
      siwa_status: status,
      siwa_code: code,
      siwa_message: message
    }
  end

  defp verify_envelope(conn, headers, opts, extra) do
    client = Keyword.fetch!(opts, :client)
    payload = conn |> http_verify_payload(headers, opts) |> Map.merge(extra)

    case client.verify_http_request(payload, audience: Keyword.fetch!(opts, :audience)) do
      {:ok,
       %{
         status: 200,
         body: %{"code" => "http_envelope_valid", "data" => data}
       }}
      when is_map(data) ->
        {:ok, data}

      {:ok, %{status: status, body: body}} when status in 400..599 ->
        {:error, status_deny_meta(status, body)}

      # Any other answer, such as a 200 without a verdict or a redirect, is no
      # verdict at all: the same as not reaching the service.
      {:ok, %{status: status}} when is_integer(status) ->
        {:error, %{reason: :siwa_request_failed, source: :siwa_http}}

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
      "path" => signed_path(conn),
      "headers" => Map.take(headers, Contract.forwarded_headers())
    }

    case {Keyword.get(opts, :body, :if_present), conn.assigns[:raw_body]} do
      {_mode, body} when is_binary(body) -> put_body_digest(payload, body)
      {:always, _missing} -> put_body_digest(payload, "")
      {:if_present, _missing} -> payload
    end
  end

  defp put_body_digest(payload, body) do
    Map.put(payload, "body_digest", Siwa.RequestAuth.content_digest_for_body(body))
  end

  defp signed_path(%Plug.Conn{request_path: path, query_string: ""}), do: path
  defp signed_path(%Plug.Conn{request_path: path, query_string: query}), do: path <> "?" <> query

  defp downcase_headers(headers) do
    Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)
  end

  defp status_deny_meta(status, body) do
    metadata = %{reason: :"siwa_http_#{status}", source: :siwa_http, siwa_status: status}

    case body do
      %{"error" => %{} = error} ->
        Enum.reduce(
          [siwa_code: "code", siwa_message: "message", siwa_hint: "hint"],
          metadata,
          fn {key, field}, metadata ->
            case error do
              %{^field => value} when is_binary(value) and value != "" ->
                Map.put(metadata, key, value)

              _error ->
                metadata
            end
          end
        )

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

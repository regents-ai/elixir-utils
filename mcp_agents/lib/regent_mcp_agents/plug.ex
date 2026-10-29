defmodule RegentMCPAgents.Plug do
  @moduledoc """
  A site's MCP address for connected apps, such as a Claude connector: the
  streamable HTTP form of the Model Context Protocol, serving the shared
  identity tools (`RegentMCPAgents.Tools`) and nothing else.

  Every message needs the person's consent: a Bearer token from the site's
  OAuth provider carrying `regent.identity.manage`. A request without one, or
  with one that is not live, is answered 401 with the challenge
  (`WWW-Authenticate: Bearer resource_metadata="<issuer>/.well-known/oauth-protected-resource", …`)
  that starts the app's sign-in. Each connected account then has its own
  request budget, counted by `RegentAgentAccess.RateLimit` under the OAuth
  subject, so one busy person never spends another's.

  A client opens with `initialize` and is answered in the protocol version it
  asked for when that is one of `protocol_versions/0`, otherwise in the newest;
  `notifications/initialized` and any other notification get 202 and no body;
  then `ping`, `tools/list` and `tools/call`. It opens no stream and issues no
  session: each POST is one JSON-RPC request answered with one JSON body. Any
  other method on the address is answered 405. While the site's OAuth provider
  or hosted identity is off, the address answers 404.

  Mount it where the site's JSON parser has run, outside any logging of
  parameters (tool calls carry pairing codes):

      forward "/mcp", RegentMCPAgents.Plug,
        app: :my_site,
        title: "My Site",
        about: "My Site, where people and their agents do one thing well.",
        rate_limit: [
          policy: "mcp",
          limit: 120,
          window: 60,
          admit: &MySite.RequestRateLimiter.admit/3
        ]

  `about` is the first sentence of the instructions the app reads; the library
  adds how to use the identity tools. `rate_limit` takes the options of
  `RegentAgentAccess.RateLimit` except `:key`, which is always the account.
  """
  @behaviour Plug
  import Plug.Conn
  alias RegentMCPAgents.Tools

  # Newest first.
  @protocol_versions ~w(2025-11-25 2025-06-18 2025-03-26)

  @guidance "This connection keeps one Regents identity for you. Call register_identity, " <>
              "then get_identity. If it is not paired, call pair_identity with the " <>
              "one-use code your person gives you, your name and your harness. " <>
              "Call check_in so your person sees you are active. Never ask for a password, " <>
              "a private key or a wallet signature."

  @doc "The MCP protocol versions this address answers in, newest first."
  def protocol_versions, do: @protocol_versions

  @impl true
  def init(opts) do
    %{
      app: Keyword.fetch!(opts, :app),
      title: Keyword.fetch!(opts, :title),
      instructions: Keyword.fetch!(opts, :about) <> " " <> @guidance,
      rate_limit:
        opts
        |> Keyword.fetch!(:rate_limit)
        |> Keyword.put(:key, &__MODULE__.account/1)
        |> RegentAgentAccess.RateLimit.init()
    }
  end

  @impl true
  def call(conn, opts) do
    cond do
      not (RegentOAuth.enabled?() and RegentMCPAgents.enabled?()) ->
        conn |> send_resp(404, "") |> halt()

      conn.method != "POST" ->
        conn
        |> put_resp_header("allow", "POST")
        |> rpc_error(405, -32_000, "Send MCP messages to this address with POST.")

      true ->
        conn = connect(conn)

        conn =
          if conn.halted, do: conn, else: RegentAgentAccess.RateLimit.call(conn, opts.rate_limit)

        if conn.halted, do: conn, else: message(conn, opts)
    end
  end

  @doc false
  def account(conn), do: conn.assigns.mcp_agent_principal.subject

  defp connect(conn) do
    scope = RegentMCPAgents.identity_scope()

    with ["Bearer " <> bearer] <- get_req_header(conn, "authorization"),
         {:ok, principal} <- RegentOAuth.verify(bearer, RegentOAuth.resource(), scope) do
      assign(conn, :mcp_agent_principal, principal)
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", RegentOAuth.challenge(scope))
        |> rpc_error(401, -32_001, "Connect your account to use this connector.")
    end
  end

  defp message(%{body_params: %{"jsonrpc" => "2.0", "method" => method} = request} = conn, opts)
       when is_binary(method) do
    case Map.fetch(request, "id") do
      {:ok, id} when is_binary(id) or is_integer(id) ->
        result = handle(method, Map.get(request, "params"), conn, opts)
        RegentOAuth.Protocol.json(conn, 200, reply(result, id))

      {:ok, _other} ->
        invalid_request(conn)

      # A notification, `notifications/initialized` among them, asks for nothing back.
      :error ->
        conn |> send_resp(202, "") |> halt()
    end
  end

  defp message(conn, _opts), do: invalid_request(conn)

  defp handle("initialize", params, _conn, opts) do
    requested = is_map(params) && params["protocolVersion"]

    {:ok,
     %{
       protocolVersion:
         if(requested in @protocol_versions, do: requested, else: hd(@protocol_versions)),
       capabilities: %{tools: %{listChanged: false}},
       serverInfo: %{
         name: Atom.to_string(opts.app),
         title: opts.title,
         version: to_string(Application.spec(opts.app, :vsn))
       },
       instructions: opts.instructions
     }}
  end

  defp handle("ping", _params, _conn, _opts), do: {:ok, %{}}

  defp handle("tools/list", _params, _conn, _opts), do: {:ok, %{tools: Tools.list()}}

  defp handle("tools/call", %{"name" => name} = params, conn, _opts) when is_binary(name) do
    if name in Tools.names() do
      arguments = Map.get(params, "arguments") || %{}

      case Tools.call(name, arguments, conn.assigns.mcp_agent_principal) do
        {:ok, answer} -> {:ok, tool_result(answer)}
        {:error, {:rate_limited, seconds}} -> {:ok, waiting(seconds)}
        _refused -> {:ok, refused()}
      end
    else
      {:error, -32_602, "Unknown tool: #{name}. Call tools/list."}
    end
  end

  defp handle("tools/call", _params, _conn, _opts),
    do: {:error, -32_602, "Name the tool to call."}

  defp handle(method, _params, _conn, _opts),
    do: {:error, -32_601, "Method not found: #{method}"}

  # The answer travels twice, as the protocol suggests: as text for a model to
  # read, and as the same object for a client that wants the fields.
  defp tool_result(answer) do
    %{
      content: [%{type: "text", text: Jason.encode!(answer)}],
      structuredContent: answer,
      isError: false
    }
  end

  defp refused do
    %{error: %{message: message, hint: hint}} = refusal = Tools.refusal()

    %{
      content: [%{type: "text", text: message <> " " <> hint}],
      structuredContent: refusal,
      isError: true
    }
  end

  defp waiting(seconds) do
    %{error: %{message: message, hint: hint}} = wait = Tools.wait(seconds)

    %{
      content: [%{type: "text", text: message <> ". " <> hint}],
      structuredContent: wait,
      isError: true
    }
  end

  defp reply({:ok, result}, id), do: %{jsonrpc: "2.0", id: id, result: result}

  defp reply({:error, code, message}, id),
    do: %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}

  defp invalid_request(conn),
    do: rpc_error(conn, 400, -32_600, "Send one JSON-RPC 2.0 request object per POST.")

  defp rpc_error(conn, status, code, message) do
    conn
    |> RegentOAuth.Protocol.json(status, %{
      jsonrpc: "2.0",
      id: nil,
      error: %{code: code, message: message}
    })
    |> halt()
  end
end

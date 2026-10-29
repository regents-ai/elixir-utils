defmodule RegentMCPAgents.Plug do
  @moduledoc """
  A site's MCP address for connected apps, such as a Claude connector: the
  streamable HTTP form of the Model Context Protocol, serving the shared
  identity tools (`RegentMCPAgents.Tools`) and, when the site names them, its
  own tools (`RegentMCPAgents.SiteTools`).

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

  A site that offers its own tools adds `tools: MySite.MCPTools` (a
  `RegentMCPAgents.SiteTools`), `endpoint: MySiteWeb.Endpoint` and
  `tool_limit: [policy: "mcp_tools", limit: 30, window: 60]`, each account's
  budget of site tool calls, counted by the same `admit` (each is a hosted
  sign-in at the SIWA service). Their calls
  run through that endpoint in this process, marked
  `conn.private[:regent_mcp_agents]`; the site leaves such a request out of its
  per-address budget. The sign-in challenge then asks for the site's permission
  too, and a connection allowed only the identity permission is answered 403
  `insufficient_scope` when it calls a site tool, so the app asks the person
  again.
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
    tools = Keyword.get(opts, :tools)

    %{
      tools: tools,
      endpoint: if(tools, do: Keyword.fetch!(opts, :endpoint)),
      tool_limit: if(tools, do: Map.new(Keyword.fetch!(opts, :tool_limit))),
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
        conn = connect(conn, opts)

        conn =
          if conn.halted, do: conn, else: RegentAgentAccess.RateLimit.call(conn, opts.rate_limit)

        if conn.halted, do: conn, else: message(conn, opts)
    end
  end

  @doc false
  def account(conn), do: conn.assigns.mcp_agent_principal.subject

  defp connect(conn, opts) do
    scope = RegentMCPAgents.identity_scope()

    with ["Bearer " <> bearer] <- get_req_header(conn, "authorization"),
         {:ok, principal} <- RegentOAuth.verify(bearer, RegentOAuth.resource(), scope) do
      assign(conn, :mcp_agent_principal, principal)
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", RegentOAuth.challenge(scopes(opts)))
        |> rpc_error(401, -32_001, "Connect your account to use this connector.")
    end
  end

  # Every permission the address's tools need, asked for together at sign-in.
  defp scopes(%{tools: nil}), do: RegentMCPAgents.identity_scope()
  defp scopes(%{tools: site}), do: RegentMCPAgents.identity_scope() <> " " <> site.scope()

  defp message(%{body_params: %{"jsonrpc" => "2.0", "method" => method} = request} = conn, opts)
       when is_binary(method) do
    case {Map.fetch(request, "id"), protocol_version(conn, method)} do
      {_id, {:unsupported, version}} ->
        rpc_error(
          conn,
          400,
          -32_600,
          "MCP-Protocol-Version #{version} isn't one this address speaks: " <>
            Enum.join(@protocol_versions, ", ") <> "."
        )

      {id, :ok} ->
        answer_message(conn, opts, method, request, id)
    end
  end

  defp message(conn, _opts), do: invalid_request(conn)

  # After initialize, the app names the version it agreed in a header; a
  # request without one is read as 2025-03-26, as the protocol says.
  defp protocol_version(_conn, "initialize"), do: :ok

  defp protocol_version(conn, _method) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] -> :ok
      [version] -> if version in @protocol_versions, do: :ok, else: {:unsupported, version}
      [version | _more] -> {:unsupported, version}
    end
  end

  defp answer_message(conn, opts, method, request, id) do
    case id do
      {:ok, id} when is_binary(id) or is_integer(id) ->
        case handle(method, Map.get(request, "params"), conn, opts) do
          # The connection wasn't allowed the site's permission: the challenge
          # asks the app to have the person allow it.
          {:insufficient_scope, scopes} ->
            conn
            |> put_resp_header(
              "www-authenticate",
              RegentOAuth.challenge(scopes) <> ~s(, error="insufficient_scope")
            )
            |> RegentOAuth.Protocol.json(
              403,
              reply({:error, -32_001, "Connect again and allow this permission."}, id)
            )

          result ->
            RegentOAuth.Protocol.json(conn, 200, reply(result, id))
        end

      {:ok, _other} ->
        invalid_request(conn)

      # A notification, `notifications/initialized` among them, asks for nothing back.
      :error ->
        conn |> send_resp(202, "") |> halt()
    end
  end

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

  defp handle("tools/list", _params, _conn, opts),
    do: {:ok, %{tools: Tools.list() ++ site_tools(opts)}}

  defp handle("tools/call", %{"name" => name} = params, conn, opts) when is_binary(name) do
    arguments = Map.get(params, "arguments") || %{}
    principal = conn.assigns.mcp_agent_principal

    cond do
      name in Tools.names() ->
        {:ok, tool_result(Tools.call(name, arguments, principal))}

      is_nil(opts.tools) ->
        unknown_tool(name)

      not Enum.any?(opts.tools.list(), &(&1.name == name)) ->
        unknown_tool(name)

      true ->
        with :ok <- spend_tool_budget(principal, opts) do
          case RegentMCPAgents.act(principal, opts.tools, opts.endpoint, name, arguments) do
            {:insufficient_scope, _scope} -> {:insufficient_scope, scopes(opts)}
            answer -> {:ok, tool_result(answer)}
          end
        end
    end
  end

  # A site tool call is signed by the hosted signer, a full sign-in each time,
  # so it has a budget of its own per account, narrower than the address's.
  defp spend_tool_budget(principal, %{tool_limit: limit, rate_limit: %{admit: admit}}) do
    case admit.({limit.policy, principal.subject}, limit.limit, limit.window) do
      {:ok, _budget} ->
        :ok

      {:error, :rate_limited, budget} ->
        {:ok,
         answer(%{
           ok: false,
           status: 429,
           retry_after: budget.reset,
           error: %{
             code: "rate_limited",
             message: "This connection has used its #{limit.limit} tool calls for now.",
             hint: "Wait the number of seconds in retry_after, then call again."
           }
         })}
    end
  end

  defp handle("tools/call", _params, _conn, _opts),
    do: {:error, -32_602, "Name the tool to call."}

  defp handle(method, _params, _conn, _opts),
    do: {:error, -32_601, "Method not found: #{method}"}

  defp unknown_tool(name), do: {:error, -32_602, "Unknown tool: #{name}. Call tools/list."}

  # The site's tools, each saying it needs the site's permission.
  defp site_tools(%{tools: nil}), do: []

  defp site_tools(%{tools: site}) do
    for tool <- site.list(),
        do: Map.put(tool, :securitySchemes, [%{type: "oauth2", scopes: [site.scope()]}])
  end

  # Every tool answers in the shape a site's browser tools answer:
  # `{ok: true, status, data}`, or `{ok: false, status, retry_after?, error}`
  # with the site's own `{code, message, hint}`. A call no site answered gives
  # the site's `refusal:` words.
  defp tool_result({:ok, data}), do: answer(%{ok: true, status: 200, data: data})

  defp tool_result({:answer, status, body, _retry_after}) when status in 200..299,
    do: answer(%{ok: true, status: status, data: body})

  defp tool_result({:answer, status, body, retry_after}) do
    error = if is_map(body["error"]), do: body["error"], else: Tools.refusal().error
    %{ok: false, status: status, error: error} |> put_retry(retry_after) |> answer()
  end

  defp tool_result({:refused, status, error}),
    do: answer(%{ok: false, status: status, error: error})

  defp tool_result(_no_answer),
    do: answer(%{ok: false, status: 502, error: Tools.refusal().error})

  defp put_retry(result, retry_after) when is_binary(retry_after) do
    case Integer.parse(retry_after) do
      {seconds, ""} -> Map.put(result, :retry_after, seconds)
      _not_seconds -> result
    end
  end

  defp put_retry(result, _none), do: result

  # The answer travels twice, as the protocol suggests: as text for a model to
  # read, and as the same object for a client that wants the fields.
  defp answer(structured) do
    %{
      content: [%{type: "text", text: Jason.encode!(structured)}],
      structuredContent: structured,
      isError: not structured.ok
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

defmodule RegentMCPAgents.Plug do
  @moduledoc "Stateless MCP reference door for identity tools; no posting or finance."
  @behaviour Plug
  import Plug.Conn
  alias RegentMCPAgents.Tools

  def init(opts), do: opts

  def call(conn, opts) do
    if RegentMCPAgents.enabled?(), do: dispatch(conn, opts), else: send_resp(conn, 404, "")
  end

  defp dispatch(
         %{method: "POST", body_params: %{"jsonrpc" => "2.0", "method" => method} = body} = conn,
         _opts
       ) do
    case method do
      "initialize" ->
        answer(conn, %{
          protocolVersion: "2025-11-25",
          serverInfo: %{name: "regent-identity", version: "0.1.0"},
          capabilities: %{tools: %{}}
        })

      "server/discover" ->
        answer(conn, %{
          resultType: "complete",
          supportedVersions: ["2026-07-28"],
          capabilities: %{tools: %{}}
        })

      "tools/list" ->
        answer(conn, %{tools: Tools.list()})

      "tools/call" ->
        run(conn, body["params"])

      "notifications/initialized" ->
        send_resp(conn, 202, "")

      _ ->
        error(conn)
    end
  end

  defp dispatch(conn, _opts), do: error(conn)

  defp run(conn, %{"name" => name, "arguments" => args}) do
    if name in Tools.names() do
      conn = Tools.authorize(conn, name)

      if conn.halted do
        conn
      else
        case Tools.call(name, args, conn.assigns.mcp_agent_principal) do
          {:ok, result} -> tool_answer(conn, result, false)
          {:error, _} -> tool_answer(conn, Tools.refusal(), true)
        end
      end
    else
      error(conn)
    end
  end

  defp run(conn, _), do: error(conn)

  defp tool_answer(conn, result, failed?),
    do:
      answer(conn, %{
        content: [%{type: "text", text: Jason.encode!(result)}],
        structuredContent: result,
        isError: failed?
      })

  defp answer(conn, result) do
    modern? = get_req_header(conn, "mcp-protocol-version") == ["2026-07-28"]
    result = if modern?, do: Map.put(result, :resultType, "complete"), else: result

    RegentOAuth.Protocol.json(conn, 200, %{
      jsonrpc: "2.0",
      id: conn.body_params["id"],
      result: result
    })
  end

  defp error(conn),
    do:
      RegentOAuth.Protocol.json(conn, 400, %{
        jsonrpc: "2.0",
        id: nil,
        error: %{code: -32602, message: "Invalid identity request."}
      })
end

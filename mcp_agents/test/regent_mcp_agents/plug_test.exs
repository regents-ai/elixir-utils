defmodule RegentMCPAgents.PlugTest do
  # Claude's connector speaks this handshake (27 Oct 2026): the address
  # challenges for sign-in, then answers initialize, the initialized
  # notification, ping and the identity tools.
  use RegentMCPAgents.Case

  @challenge ~s(Bearer resource_metadata="http://localhost:4000/.well-known/oauth-protected-resource")

  test "a request without a live token is asked to sign in" do
    for token <- [nil, "not-a-token"] do
      conn = mcp(rpc("initialize", %{"protocolVersion" => "2025-06-18"}), token)

      assert conn.status == 401
      assert [challenge] = Plug.Conn.get_resp_header(conn, "www-authenticate")
      assert String.starts_with?(challenge, @challenge)
      assert challenge =~ ~s(scope="regent.identity.manage")
      assert %{"error" => %{"code" => -32_001}} = json(conn)
    end
  end

  test "initialize answers in the version the app asks for when it is supported, else the newest" do
    for {asked, answered} <- [
          {"2025-06-18", "2025-06-18"},
          {"2025-03-26", "2025-03-26"},
          {"1999-01-01", hd(RegentMCPAgents.Plug.protocol_versions())},
          {nil, hd(RegentMCPAgents.Plug.protocol_versions())}
        ] do
      token = token!("did:privy:#{asked}")
      conn = mcp(rpc("initialize", %{"protocolVersion" => asked}, "init"), token)
      assert conn.status == 200

      assert %{"jsonrpc" => "2.0", "id" => "init", "result" => result} = json(conn)
      assert result["protocolVersion"] == answered
      assert result["capabilities"] == %{"tools" => %{"listChanged" => false}}

      assert result["serverInfo"] == %{
               "name" => "regent_mcp_agents",
               "title" => "Test Site",
               "version" => "0.1.0"
             }

      assert result["instructions"] =~
               ~r/\ATest Site, where people .* Call register_identity, then get_identity\./
    end
  end

  test "the initialized notification is accepted with no body, and ping answers" do
    token = token!("did:privy:sol")

    conn = mcp(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, token)
    assert conn.status == 202
    assert conn.resp_body == ""

    assert %{"id" => 7, "result" => %{}} = json(mcp(rpc("ping", %{}, 7), token))
  end

  test "tools/list offers the identity tools, pairing as one of the site's hosted runtimes" do
    conn = mcp(rpc("tools/list"), token!("did:privy:sol"))
    assert %{"result" => %{"tools" => tools}} = json(conn)

    assert Enum.map(tools, & &1["name"]) ==
             ~w(register_identity get_identity pair_identity check_in)

    pair = Enum.find(tools, &(&1["name"] == "pair_identity"))
    assert pair["inputSchema"]["properties"]["harness"]["enum"] == ["claude"]
    assert pair["inputSchema"]["required"] == ["code", "name", "harness"]
  end

  test "a refused tool call gives the site's refusal words, or the plain default" do
    token = token!("did:privy:sol")
    call = rpc("tools/call", %{"name" => "get_identity", "arguments" => %{"extra" => 1}})

    assert %{"result" => %{"isError" => true, "structuredContent" => answer}} =
             json(mcp(call, token))

    assert %{"ok" => false, "status" => 502, "error" => error} = answer
    assert error["message"] == "The identity request could not be completed."

    assert error["hint"] ==
             "Connect your Regents account, register the connection, and check its pairing on the Agents page."

    config = Application.fetch_env!(:regent_mcp_agents, :config)
    on_exit(fn -> Application.put_env(:regent_mcp_agents, :config, config) end)

    Application.put_env(
      :regent_mcp_agents,
      :config,
      Keyword.put(config, :refusal, "Check your pairing on your Keyfleet Agents page.")
    )

    assert %{"result" => %{"structuredContent" => %{"error" => error}}} = json(mcp(call, token))
    assert error["hint"] == "Check your pairing on your Keyfleet Agents page."
  end

  test "each connected account has its own request budget" do
    sol = token!("did:privy:sol")
    ana = token!("did:privy:ana")

    for _ <- 1..3, do: assert(mcp(rpc("ping"), sol).status == 200)

    limited = mcp(rpc("ping"), sol)
    assert limited.status == 429
    assert Plug.Conn.get_resp_header(limited, "retry-after") == ["60"]

    ok = mcp(rpc("ping"), ana)
    assert ok.status == 200
    assert Plug.Conn.get_resp_header(ok, "ratelimit") == [~s("mcp";r=2;t=60)]

    assert Enum.sort(RegentMCPAgents.Test.Limiter.keys()) ==
             [{"mcp", "did:privy:ana"}, {"mcp", "did:privy:sol"}]
  end

  test "unknown methods and tools, and malformed requests, get JSON-RPC errors" do
    token = token!("did:privy:sol")

    assert %{"error" => %{"code" => -32_601}} = json(mcp(rpc("resources/list"), token))

    assert %{"error" => %{"code" => -32_602}} =
             json(mcp(rpc("tools/call", %{"name" => "ask_question"}), token))

    conn = mcp(%{"jsonrpc" => "1.0", "id" => 1, "method" => "ping"}, token)
    assert conn.status == 400
    assert %{"error" => %{"code" => -32_600}} = json(conn)
  end

  test "the address takes only POST, and answers 404 while hosted identity is off" do
    conn = mcp(%{}, nil, :get)
    assert conn.status == 405
    assert Plug.Conn.get_resp_header(conn, "allow") == ["POST"]

    config = Application.fetch_env!(:regent_mcp_agents, :config)
    on_exit(fn -> Application.put_env(:regent_mcp_agents, :config, config) end)
    Application.put_env(:regent_mcp_agents, :config, Keyword.put(config, :enabled?, false))

    assert mcp(rpc("initialize"), token!("did:privy:sol")).status == 404
  end
end

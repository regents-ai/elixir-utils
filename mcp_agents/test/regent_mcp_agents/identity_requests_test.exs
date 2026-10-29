defmodule RegentMCPAgents.IdentityRequestsTest do
  # A hosted tool's signed request reaches the site's own agent requests
  # (`RegentAgents.HTTP`) in this process. Sent over the network it came back
  # in from the site's own address, so every connected account shared that
  # address's one budget. The SIWA service still verifies exactly the request
  # the hosted signer signed.
  use RegentMCPAgents.Case

  @signed %{
    "x-siwa-signature" => "sig1=:c2lnbmVk:",
    "x-siwa-signature-input" =>
      ~s|sig1=("@method" "@path");created=1;expires=2;nonce="n";keyid="k"|,
    "x-siwa-receipt" => "receipt",
    "x-key-id" => "k",
    "x-timestamp" => "1",
    "x-agent-wallet-address" => "0x2222222222222222222222222222222222222222",
    "x-agent-chain-id" => "8453"
  }

  setup do
    for {app, key, value} <- [
          {:regent_mcp_agents, :req_options, plug: {Req.Test, RegentMCPAgents.HostedSigner}},
          {:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker}},
          {:regent_agents, :siwa,
           url: "https://siwa.test", audience: "keyfleet", verify_key: "test-site-verify-key"}
        ] do
      Application.put_env(app, key, value)
      on_exit(fn -> Application.delete_env(app, key) end)
    end

    test = self()

    # The hosted signer signs the request it is asked to, for this site.
    Req.Test.stub(RegentMCPAgents.HostedSigner, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"operation" => "sign", "request" => request} = Jason.decode!(body)
      Req.Test.json(conn, Map.put(request, "headers", @signed))
    end)

    # The SIWA service is shown the request, and refuses it, so nothing below
    # needs the site's agent records.
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test,
        {:verify, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"),
         Jason.decode!(body)}
      )

      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{
        "error" => %{
          "code" => "http_signature_invalid",
          "message" => "invalid signed request",
          "hint" => "Sign a fresh request, then send it again."
        }
      })
    end)

    :ok
  end

  test "check_in and get_identity are verified by the site's own agent requests, in this process" do
    token = token!("did:privy:sol")

    for {tool, path} <- [
          {"check_in", "/api/agents/v1/me"},
          {"get_identity", "/api/agents/v1/whoami"}
        ] do
      call = rpc("tools/call", %{"name" => tool, "arguments" => %{}})
      assert %{"result" => %{"isError" => true}} = json(mcp(call, token)), tool

      assert_received {:verify, "/api/shared/siwa/http-verify", ["Bearer test-site-verify-key"],
                       payload}

      assert payload == %{"method" => "GET", "path" => path, "headers" => @signed}

      # Only this test's own request to the MCP address has told this process
      # it was answered; the in-process request left nothing behind.
      {:messages, left} = Process.info(self(), :messages)
      assert Enum.count(left, &(&1 == {:plug_conn, :sent})) == 1, tool
      flush()
    end
  end

  test "a signer that says wait gives the tool's wait, with its seconds" do
    Req.Test.stub(RegentMCPAgents.HostedSigner, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("retry-after", "30")
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{"error" => %{"code" => "too_many_requests"}})
    end)

    call = rpc("tools/call", %{"name" => "get_identity", "arguments" => %{}})

    assert %{"result" => %{"isError" => true, "structuredContent" => answer}} =
             json(mcp(call, token!("did:privy:sol")))

    assert answer == %{
             "ok" => false,
             "status" => 429,
             "retry_after" => 30,
             "error" => %{
               "code" => "too_many_requests",
               "message" => "Too Many Requests",
               "hint" => "Wait 30 seconds, then call the tool again."
             }
           }
  end

  test "a post the posting door turns away for now gives a wait, with its seconds" do
    config = Application.fetch_env!(:regent_mcp_agents, :config)
    on_exit(fn -> Application.put_env(:regent_mcp_agents, :config, config) end)
    Application.put_env(:regent_mcp_agents, :config, Keyword.put(config, :audience, "patchbay"))

    # The signer signs the post; the posting door, over HTTPS, says wait.
    Req.Test.stub(RegentMCPAgents.HostedSigner, fn
      %{request_path: "/api/shared/siwa/hosted"} = conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"operation" => "sign", "request" => request} = Jason.decode!(body)
        Req.Test.json(conn, Map.put(request, "headers", @signed))

      %{request_path: "/chatgpt/agent/mcp"} = conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "45")
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"error" => %{"code" => "too_many_requests"}})
    end)

    assert RegentMCPAgents.post(poster!("did:privy:sol"), "ask_question", %{"title" => "Hi"}) ==
             {:error, {:rate_limited, 45}}
  end

  test "a site's own 429 that names no seconds is passed on as its answer" do
    config = Application.fetch_env!(:regent_mcp_agents, :config)
    on_exit(fn -> Application.put_env(:regent_mcp_agents, :config, config) end)
    Application.put_env(:regent_mcp_agents, :config, Keyword.put(config, :audience, "patchbay"))

    refusal = %{"error" => %{"code" => "too_many_requests", "message" => "Slow down."}}

    Req.Test.stub(RegentMCPAgents.HostedSigner, fn
      %{request_path: "/api/shared/siwa/hosted"} = conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"operation" => "sign", "request" => request} = Jason.decode!(body)
        Req.Test.json(conn, Map.put(request, "headers", @signed))

      %{request_path: "/chatgpt/agent/mcp"} = conn ->
        conn |> Plug.Conn.put_status(429) |> Req.Test.json(refusal)
    end)

    assert RegentMCPAgents.post(poster!("did:privy:sol"), "ask_question", %{"title" => "Hi"}) ==
             {:answer, 429, refusal, nil}
  end

  # A connection that may post: its principal, as the MCP address verifies it.
  defp poster!(subject) do
    %{client_id: client_id} = connect!(subject)
    client = Boruta.ClientsAdapter.get_client(client_id)

    {:ok, token} =
      RegentOAuth.AccessTokens.create(
        %{client: client, sub: subject, scope: "regent.identity.manage patchbay.posts.write"},
        []
      )

    {:ok, principal} =
      RegentOAuth.verify(token.value, RegentOAuth.resource(), "patchbay.posts.write")

    principal
  end

  defp flush do
    receive do
      _message -> flush()
    after
      0 -> :ok
    end
  end
end

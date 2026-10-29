defmodule RegentMCPAgents.HostedIdentityTest do
  # A connected app's one hosted identity, end to end through the MCP address:
  # the hosted signer signs, the site's own agent requests verify the signed
  # request in process, and the site's agent records keep the pairing.
  use RegentMCPAgents.Case

  alias RegentAgents.Person

  @wallet "0x2222222222222222222222222222222222222222"
  @site_key String.duplicate("k", 32)
  @signed %{
    "x-siwa-signature" => "sig1=:c2lnbmVk:",
    "x-siwa-signature-input" =>
      ~s|sig1=("@method" "@path");created=1;expires=2;nonce="n";keyid="k"|,
    "x-siwa-receipt" => "receipt",
    "x-key-id" => "k",
    "x-timestamp" => "1",
    "x-agent-wallet-address" => @wallet,
    "x-agent-chain-id" => "8453"
  }

  # Every request the hosted signer may be asked to sign.
  @signable [
    {"GET", "/api/agents/v1/whoami"},
    {"GET", "/api/agents/v1/me"},
    {"POST", "/api/agents/v1/pair"}
  ]

  setup do
    for {app, key, value} <- [
          {:regent_mcp_agents, :req_options, plug: {Req.Test, RegentMCPAgents.HostedSigner}},
          {:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker}},
          {:regent_agents, :siwa, url: "https://siwa.test", audience: "keyfleet"}
        ] do
      Application.put_env(app, key, value)
      on_exit(fn -> Application.delete_env(app, key) end)
    end

    test = self()

    # The hosted signer, asked with the site's key: it registers the identity
    # and signs the request it is asked to, as the one hosted wallet.
    Req.Test.stub(RegentMCPAgents.HostedSigner, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      asked = Jason.decode!(body)
      send(test, {:signer, Plug.Conn.get_req_header(conn, "authorization"), body, asked})

      case asked do
        %{"operation" => "register"} ->
          Req.Test.json(conn, %{"address" => @wallet})

        %{"operation" => "sign", "request" => request} ->
          Req.Test.json(conn, Map.put(request, "headers", @signed))
      end
    end)

    # The SIWA service verifies the signed request as the hosted wallet's, for
    # this site's audience.
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test,
        {:verify, conn.req_headers, Plug.Conn.get_req_header(conn, "x-siwa-audience"), body,
         Jason.decode!(body)}
      )

      Req.Test.json(conn, %{
        "code" => "http_envelope_valid",
        "data" => %{
          "verified" => true,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => @wallet,
            "chain_id" => 8453,
            "audience" => "keyfleet"
          },
          "agentRegistration" => nil,
          "agentBook" => nil
        }
      })
    end)

    :ok
  end

  defp person(subject), do: %Person{privy_user_id: subject}

  defp agents(subject), do: RegentAgents.list_my_agents!(actor: person(subject))

  defp pair!(token, subject) do
    arguments = %{"code" => code!(subject), "name" => "Claude", "harness" => "claude"}
    assert %{"isError" => false} = tool(token, "pair_identity", arguments)
    [agent] = agents(subject)
    agent
  end

  defp signed_requests do
    receive do
      {:signer, _auth, _body, %{"operation" => "sign", "request" => request}} ->
        [request | signed_requests()]

      {:signer, _auth, _body, _register} ->
        signed_requests()
    after
      0 -> []
    end
  end

  defp verified_paths do
    receive do
      {:verify, _headers, _audience, _body, payload} -> [payload["path"] | verified_paths()]
    after
      0 -> []
    end
  end

  test "pair_identity's POST is verified in process with the exact body the hosted signer signed" do
    token = token!("did:privy:sol")
    code = code!("did:privy:sol")
    arguments = %{"code" => code, "name" => "Claude", "harness" => "claude"}

    assert %{"isError" => false, "structuredContent" => %{"ok" => true, "data" => answer}} =
             tool(token, "pair_identity", arguments)

    assert answer["paired"] == true

    assert_received {:signer, _auth, _body,
                     %{
                       "operation" => "sign",
                       "request" =>
                         %{"method" => "POST", "path" => "/api/agents/v1/pair"} = signed
                     }}

    assert Jason.decode!(signed["body"]) == arguments

    assert_received {:verify, _headers, ["keyfleet"], _raw, payload}

    assert payload == %{
             "method" => "POST",
             "path" => "/api/agents/v1/pair",
             "headers" => @signed,
             "body_digest" => Siwa.content_digest_for_body(signed["body"])
           }

    # An ordinary paired agent of the authorizing account, as the hosted wallet.
    assert [%{harness: :claude, wallet: @wallet, name: "Claude"}] = agents("did:privy:sol")
  end

  test "a pairing code must belong to the authorizing account; another's is refused before anything is signed" do
    token = token!("did:privy:sol")
    arguments = %{"code" => code!("did:privy:ana"), "name" => "Claude", "harness" => "claude"}

    assert %{"isError" => true, "structuredContent" => %{"error" => error}} =
             tool(token, "pair_identity", arguments)

    assert error["code"] == "pairing_code_unknown"
    assert signed_requests() == []
    assert agents("did:privy:sol") == [] and agents("did:privy:ana") == []
  end

  test "the hosted signer signs only the identity requests, for one identity, and the connection's token never leaves the site" do
    %{access: token} = connect!("did:privy:sol")

    assert %{"isError" => false} = tool(token, "register_identity")
    assert %{"isError" => false} = tool(token, "get_identity")
    pair!(token, "did:privy:sol")
    assert %{"isError" => false} = tool(token, "check_in")

    # Neither an unknown tool nor extra arguments reach the signer.
    RegentMCPAgents.Test.Limiter.reset()
    assert %{"error" => _} = json(mcp(rpc("tools/call", %{"name" => "ask_question"}), token))
    assert %{"isError" => true} = tool(token, "get_identity", %{"path" => "/api/anything"})

    key = RegentMCPAgents.identity_key("keyfleet", "did:privy:sol")
    asked = collect_signer()
    assert length(asked) == 4

    for {auth, raw, request} <- asked do
      # Asked with the site's own hosted signing key, for the account's one identity.
      assert auth == ["Bearer " <> @site_key]
      assert request["identity_key"] == key
      refute raw =~ token
    end

    signed = for {_, _, %{"operation" => "sign", "request" => r}} <- asked, do: r
    assert Enum.map(signed, &{&1["method"], &1["path"]}) -- @signable == []
    assert length(signed) == 3

    for _ <- signed do
      assert_received {:verify, headers, ["keyfleet"], raw, payload}
      refute raw =~ token
      refute Enum.any?(headers, fn {_name, value} -> value =~ token end)
      assert payload["headers"] == @signed
    end
  end

  test "reconnecting or refreshing keeps the account's one hosted identity; another account has its own" do
    first = connect!("did:privy:sol")
    again = connect!("did:privy:sol")
    assert {200, %{"access_token" => refreshed}} = refresh(first.client_id, first.refresh)

    ids =
      for token <- [first.access, again.access, refreshed] do
        assert %{"isError" => false, "structuredContent" => %{"data" => answer}} =
                 tool(token, "register_identity")

        answer["identity_id"]
      end

    assert Enum.uniq(ids) == [RegentMCPAgents.identity_key("keyfleet", "did:privy:sol")]

    assert %{"structuredContent" => %{"data" => %{"identity_id" => other}}} =
             tool(token!("did:privy:ana"), "register_identity")

    refute other in ids

    # The reconnected app finds the pairing it made, and pairing again makes no second agent.
    agent = pair!(first.access, "did:privy:sol")

    assert %{"structuredContent" => %{"data" => %{"paired" => true}}} =
             tool(refreshed, "get_identity")
    assert %{"isError" => false} = tool(again.access, "check_in")
    assert [%{id: id}] = agents("did:privy:sol")
    assert id == agent.id
  end

  test "only a check-in moves the agent's last check-in; ping, the handshake, a refresh and the identity probe leave it" do
    %{client_id: client, access: token, refresh: refresh_token} = connect!("did:privy:sol")
    %{last_contact_at: paired_at} = pair!(token, "did:privy:sol")

    RegentMCPAgents.Test.Limiter.reset()
    assert mcp(rpc("initialize", %{"protocolVersion" => "2025-06-18"}), token).status == 200

    assert mcp(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, token).status ==
             202

    assert mcp(rpc("ping"), token).status == 200
    assert {200, %{"access_token" => refreshed}} = refresh(client, refresh_token)
    assert %{"isError" => false} = tool(refreshed, "register_identity")
    assert %{"isError" => false} = tool(refreshed, "get_identity")

    assert [%{last_contact_at: ^paired_at}] = agents("did:privy:sol")
    refute "/api/agents/v1/me" in verified_paths()

    assert %{"isError" => false} = tool(refreshed, "check_in")
    assert [%{last_contact_at: checked_in}] = agents("did:privy:sol")
    assert DateTime.after?(checked_in, paired_at)
  end

  test "an unpaired connection stays unpaired: a check-in is refused and pairs nothing again" do
    token = token!("did:privy:sol")
    agent = pair!(token, "did:privy:sol")

    :ok = RegentAgents.unpair_agent!(agent, actor: person("did:privy:sol"))

    assert %{"isError" => true} = tool(token, "check_in")
    assert %{"structuredContent" => %{"data" => %{"paired" => false}}} =
             tool(token, "get_identity")
    assert agents("did:privy:sol") == []
  end

  test "disconnecting the app revokes its access and refresh tokens: the next call is asked to sign in" do
    %{client_id: client, access: token, refresh: refresh_token} = connect!("did:privy:sol")
    assert %{"isError" => false} = tool(token, "register_identity")

    assert {:ok, :ok} = RegentOAuth.revoke_client("did:privy:sol", client)

    conn = mcp(rpc("tools/call", %{"name" => "check_in", "arguments" => %{}}), token)
    assert conn.status == 401
    assert [_challenge] = Plug.Conn.get_resp_header(conn, "www-authenticate")
    assert {400, %{"error" => "invalid_grant"}} = refresh(client, refresh_token)
  end

  defp collect_signer do
    receive do
      {:signer, auth, raw, asked} -> [{auth, raw, asked} | collect_signer()]
    after
      0 -> []
    end
  end
end

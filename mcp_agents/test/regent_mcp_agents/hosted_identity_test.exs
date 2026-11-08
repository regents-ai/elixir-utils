defmodule RegentMCPAgents.HostedIdentityTest do
  # A connected app's one hosted identity, end to end through the MCP address:
  # the hosted signer signs, the site's own agent requests verify the signed
  # request in process, and the site's agent records keep the pairing.
  use RegentMCPAgents.Case

  alias RegentAgents.Person

  @site_key String.duplicate("k", 32)
  @signed %{
    "x-siwa-signature" => "sig1=:c2lnbmVk:",
    "x-siwa-signature-input" =>
      ~s|sig1=("@method" "@path");created=1;expires=2;nonce="n";keyid="k"|,
    "x-siwa-receipt" => "receipt",
    "x-key-id" => "k",
    "x-timestamp" => "1",
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
    # and signs the request it is asked to, as that identity's own wallet.
    Req.Test.stub(RegentMCPAgents.HostedSigner, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      asked = Jason.decode!(body)
      send(test, {:signer, Plug.Conn.get_req_header(conn, "authorization"), body, asked})
      wallet = wallet(asked["identity_key"])

      case asked do
        %{"operation" => "register"} ->
          Req.Test.json(conn, %{"address" => wallet})

        %{"operation" => "sign", "request" => request} ->
          headers = Map.put(@signed, "x-agent-wallet-address", wallet)
          Req.Test.json(conn, Map.put(request, "headers", headers))
      end
    end)

    # The SIWA service verifies the signed request as the signing wallet's, for
    # this site's audience.
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      payload = Jason.decode!(body)

      send(
        test,
        {:verify, conn.req_headers, Plug.Conn.get_req_header(conn, "x-siwa-audience"), body,
         payload}
      )

      Req.Test.json(conn, %{
        "code" => "http_envelope_valid",
        "data" => %{
          "verified" => true,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => payload["headers"]["x-agent-wallet-address"],
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

  # Each hosted identity has its own wallet.
  defp wallet(identity_key), do: "0x" <> binary_part(identity_key, 0, 40)

  defp key(subject, client), do: RegentMCPAgents.identity_key("keyfleet", subject, client)

  defp person(subject), do: %Person{privy_user_id: subject}

  defp agents(subject), do: RegentAgents.list_my_agents!(actor: person(subject))

  defp pair!(token, subject) do
    arguments = %{"code" => code!(subject), "name" => "Claude", "harness" => "claude"}
    assert %{"isError" => false} = tool(token, "pair_identity", arguments)
    principal = principal!(token)
    wallet = wallet(key(subject, principal.client_id))
    [agent] = Enum.filter(agents(subject), &(&1.wallet == wallet))
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
    %{client_id: client, access: token} = connect!("did:privy:sol")
    wallet = wallet(key("did:privy:sol", client))
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
    # Signed for this site's own host, the one the request is then sent to.
    assert signed["authority"] == "localhost:4000"

    assert_received {:verify, _headers, ["keyfleet"], _raw, payload}

    assert payload == %{
             "method" => "POST",
             "path" => "/api/agents/v1/pair",
             "authority" => "localhost:4000",
             "headers" => Map.put(@signed, "x-agent-wallet-address", wallet),
             "body_digest" => Siwa.content_digest_for_body(signed["body"])
           }

    # An ordinary paired agent of the authorizing account, as this app's hosted wallet.
    assert [%{harness: :claude, wallet: ^wallet, name: "Claude"}] = agents("did:privy:sol")
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
    %{client_id: client, access: token} = connect!("did:privy:sol")

    assert %{"isError" => false} = tool(token, "register_identity")
    assert %{"isError" => false} = tool(token, "get_identity")
    pair!(token, "did:privy:sol")
    assert %{"isError" => false} = tool(token, "check_in")

    # Neither an unknown tool nor extra arguments reach the signer.
    RegentMCPAgents.Test.Limiter.reset()
    assert %{"error" => _} = json(mcp(rpc("tools/call", %{"name" => "ask_question"}), token))
    assert %{"isError" => true} = tool(token, "get_identity", %{"path" => "/api/anything"})

    key = key("did:privy:sol", client)
    asked = collect_signer()
    assert length(asked) == 4

    for {auth, raw, request} <- asked do
      # Asked with the site's own hosted signing key, for this app's one identity.
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
      assert payload["headers"] == Map.put(@signed, "x-agent-wallet-address", wallet(key))
    end
  end

  test "one app keeps its identity across refreshed tokens; every other app, and every other account, has its own" do
    first = connect!("did:privy:sol")
    assert {200, %{"access_token" => refreshed}} = refresh(first.client_id, first.refresh)

    # The same app, before and after a refresh: one identity, one address.
    answers =
      for token <- [first.access, refreshed] do
        assert %{"isError" => false, "structuredContent" => %{"data" => answer}} =
                 tool(token, "register_identity")

        answer
      end

    assert [%{"identity_id" => id}] = Enum.uniq_by(answers, & &1["identity_id"])
    assert id == key("did:privy:sol", first.client_id)

    # A second app the same account connects: its own key and its own address.
    second = connect!("did:privy:sol")
    refute second.client_id == first.client_id

    assert %{"structuredContent" => %{"data" => %{"identity_id" => second_id}}} =
             tool(second.access, "register_identity")

    assert second_id == key("did:privy:sol", second.client_id)
    refute second_id == id
    refute wallet(second_id) == wallet(id)

    assert %{"structuredContent" => %{"data" => %{"identity_id" => other}}} =
             tool(token!("did:privy:ana"), "register_identity")

    refute other in [id, second_id]

    # The refreshed token finds the pairing its app made; pairing again makes no second agent.
    agent = pair!(first.access, "did:privy:sol")

    assert %{"structuredContent" => %{"data" => %{"paired" => true}}} =
             tool(refreshed, "get_identity")

    assert %{"isError" => false} = tool(refreshed, "check_in")
    assert [%{id: id_paired}] = agents("did:privy:sol")
    assert id_paired == agent.id
  end

  test "a second app of an account already paired gets no pairing until it pairs with its own code" do
    first = connect!("did:privy:sol")
    first_agent = pair!(first.access, "did:privy:sol")

    second = connect!("did:privy:sol")

    assert %{"structuredContent" => %{"data" => %{"paired" => false}}} =
             tool(second.access, "get_identity")

    assert %{"isError" => true} = tool(second.access, "check_in")
    assert [%{id: only}] = agents("did:privy:sol")
    assert only == first_agent.id

    # Paired with a code of its own, it is a second agent with its own wallet.
    second_agent = pair!(second.access, "did:privy:sol")
    refute second_agent.id == first_agent.id
    refute second_agent.wallet == first_agent.wallet
    assert second_agent.wallet == wallet(key("did:privy:sol", second.client_id))

    assert %{"structuredContent" => %{"data" => %{"paired" => true}}} =
             tool(second.access, "get_identity")

    assert length(agents("did:privy:sol")) == 2
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

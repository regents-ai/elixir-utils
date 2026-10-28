defmodule RegentAgents.HTTPTest do
  use RegentAgents.Case, async: true

  import Plug.Test

  @wallet "0x2222222222222222222222222222222222222222"

  defp send_request(method, path, body \\ nil) do
    conn =
      case body do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end

    conn = RegentAgents.Test.Router.call(conn, RegentAgents.Test.Router.init([]))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp put_req_header(conn, key, value), do: Plug.Conn.put_req_header(conn, key, value)

  @listing "https://www.8004scan.io/agents/base/97609"

  # The SIWA service verifies the request, names the key that signed it, its
  # listing in the agent registry and the World ID person behind it, if any.
  defp siwa_verifies(
         wallet \\ String.upcase(@wallet),
         audience \\ "test",
         registration \\ nil,
         book \\ nil
       ) do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        self(),
        {:verified, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"),
         Jason.decode!(body)}
      )

      Req.Test.json(conn, %{
        "code" => "http_envelope_valid",
        "data" => %{
          "verified" => true,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => "0x" <> String.slice(wallet, 2..-1//1),
            "chain_id" => 8453,
            "audience" => audience
          },
          "agentRegistration" => registration,
          "agentBook" => book
        }
      })
    end)
  end

  defp siwa_refuses(status, code) do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{
        "error" => %{
          "code" => code,
          "message" => "This signed request was already used.",
          "hint" => "Sign a fresh request with a new nonce, then send it again."
        }
      })
    end)
  end

  test "an agent pairs with a code, signed for this site, and checks in on the pairing" do
    owner = person("sol")
    code = code!(owner)
    siwa_verifies()

    body = %{"code" => code, "name" => "Sol", "harness" => "codex"}
    assert {201, %{"data" => paired}} = send_request(:post, "/api/agents/v1/pair", body)
    assert %{"name" => "Sol", "harness" => "codex", "wallet" => @wallet} = paired
    assert paired["registry_listing"] == nil
    assert paired["human_backed"] == false
    assert paired["same_person_agent_count"] == nil

    assert_received {:verified, "/api/shared/siwa/http-verify", ["Bearer test-site-verify-key"],
                     envelope}

    assert %{"method" => "POST", "path" => "/api/agents/v1/pair", "body_digest" => digest} =
             envelope

    assert digest == Siwa.content_digest_for_body(Jason.encode!(body))
    refute Map.has_key?(envelope, "body")

    assert {200, %{"data" => checked_in}} = send_request(:get, "/api/agents/v1/me")
    assert checked_in["wallet"] == @wallet
    assert checked_in["account"] == %{"display_name" => "Person did:privy:sol"}

    assert_received {:verified, _path, _authorization,
                     %{"method" => "GET", "path" => "/api/agents/v1/me"} = check_in}

    refute Map.has_key?(check_in, "body_digest")
  end

  test "a listed, human-backed agent is answered with its listing's page and its saved backing, never the person's number" do
    owner = person("listed")
    code = code!(owner)

    siwa_verifies(
      @wallet,
      "test",
      %{
        "agentId" => "eip155:8453:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432:97609",
        "tokenId" => "97609",
        "profileUrl" => "https://siwa.regents.sh/agent-profiles/abc",
        "registryUrl" => @listing
      },
      %{"humanId" => "0x" <> String.duplicate("ab", 32), "agentCount" => 3}
    )

    body = %{"code" => code, "name" => "Listed", "harness" => "hermes"}

    backed = %{
      "registry_listing" => @listing,
      "human_backed" => true,
      "same_person_agent_count" => 3
    }

    assert {201, %{"data" => paired}} = send_request(:post, "/api/agents/v1/pair", body)
    assert Map.take(paired, Map.keys(backed)) == backed

    assert {200, %{"data" => me}} = send_request(:get, "/api/agents/v1/me")
    assert Map.take(me, Map.keys(backed)) == backed

    assert {200, %{"data" => %{"agent" => agent}}} = send_request(:get, "/api/agents/v1/whoami")
    assert Map.take(agent, Map.keys(backed)) == backed

    refute Jason.encode!(me) =~ String.duplicate("ab", 32)
    refute Jason.encode!(agent) =~ String.duplicate("ab", 32)
    assert [%{same_person_agent_count: 3} = saved] = RegentAgents.list_my_agents!(actor: owner)
    assert saved.human_id == "0x" <> String.duplicate("ab", 32)

    # The first person stays for good: a request naming nobody, or someone else,
    # leaves them and their count in place.
    for book <- [nil, %{"humanId" => "0x" <> String.duplicate("cd", 32), "agentCount" => 1}] do
      siwa_verifies(@wallet, "test", nil, book)

      assert {200, %{"data" => %{"human_backed" => true, "same_person_agent_count" => 3}}} =
               send_request(:get, "/api/agents/v1/me")

      assert [%{human_id: "0x" <> first, same_person_agent_count: 3}] =
               RegentAgents.list_my_agents!(actor: owner)

      assert first == String.duplicate("ab", 32)
    end

    # A request naming the same person saves their new count.
    siwa_verifies(@wallet, "test", nil, %{
      "humanId" => "0x" <> String.duplicate("ab", 32),
      "agentCount" => 4
    })

    assert {200, %{"data" => %{"human_backed" => true, "same_person_agent_count" => 4}}} =
             send_request(:get, "/api/agents/v1/me")
  end

  test "an unknown harness is named before anything is signed for" do
    body = %{"code" => code!(person("new")), "name" => "New", "harness" => "hal"}
    assert {400, %{"error" => error}} = send_request(:post, "/api/agents/v1/pair", body)
    assert error["code"] == "harness_unknown"
    assert error["hint"] =~ "claude_code"
    assert error["hint"] =~ "other"
    refute_received {:verified, _path, _authorization, _envelope}
  end

  # Invariant: an agent's name shows on every Regent site, so a name holding a
  # hidden character is refused with its own code and the code stays unused.
  test "a name with a hidden character cannot pair, and the code still works" do
    siwa_verifies()
    body = %{"code" => code!(person("hidden")), "name" => "Sol\u202Eexe", "harness" => "muse"}

    assert {400, %{"error" => %{"code" => "invalid_name", "hint" => hint}}} =
             send_request(:post, "/api/agents/v1/pair", body)

    assert hint =~ "hidden characters"
    assert {201, _paired} = send_request(:post, "/api/agents/v1/pair", %{body | "name" => "Sol"})
  end

  test "a missing field, an extra field or a used code cannot pair" do
    siwa_verifies()
    code = code!(person("used"))
    body = %{"code" => code, "name" => "Sol", "harness" => "muse"}

    assert {400, %{"error" => %{"code" => "pairing_failed"}}} =
             send_request(:post, "/api/agents/v1/pair", Map.delete(body, "name"))

    assert {400, %{"error" => %{"code" => "pairing_failed"}}} =
             send_request(:post, "/api/agents/v1/pair", Map.put(body, "extra", "x"))

    assert {201, _paired} = send_request(:post, "/api/agents/v1/pair", body)

    assert {400, %{"error" => %{"code" => "pairing_failed", "hint" => _hint}}} =
             send_request(:post, "/api/agents/v1/pair", body)
  end

  # Invariant: every signed agent is told which of the three statuses it is in,
  # what the site lets it do in that status and its next step, and a check-in is
  # refused until it acts for its person.
  test "whoami names the agent's status, what it may do and its next step" do
    siwa_verifies()
    allowed = Application.fetch_env!(:regent_agents, :allowed)

    assert {200, %{"data" => unpaired}} = send_request(:get, "/api/agents/v1/whoami")

    assert %{"authenticated" => true, "pairing" => nil, "status" => "not_paired"} = unpaired
    assert unpaired["allowed"] == allowed["not_paired"]
    assert is_binary(unpaired["next_step"])
    refute Map.has_key?(unpaired, "effective_access")

    assert {403, %{"error" => %{"code" => "agent_not_paired"}}} =
             send_request(:get, "/api/agents/v1/me")

    away = person("away")
    body = %{"code" => code!(away), "name" => "Sol", "harness" => "codex"}
    assert {201, _paired} = send_request(:post, "/api/agents/v1/pair", body)

    assert {200, %{"data" => %{"status" => "person_not_here", "pairing" => %{}} = waiting}} =
             send_request(:get, "/api/agents/v1/whoami")

    assert waiting["allowed"] == allowed["person_not_here"]
    assert is_binary(waiting["next_step"])

    assert {403, %{"error" => %{"code" => "person_not_here"}}} =
             send_request(:get, "/api/agents/v1/me")

    [agent] = RegentAgents.list_my_agents!(actor: away)
    RegentAgents.unpair_agent!(agent, actor: away)
    body = %{body | "code" => code!(person("here"))}
    assert {201, _paired} = send_request(:post, "/api/agents/v1/pair", body)

    assert {200, %{"data" => %{"status" => "paired", "next_step" => nil} = acting}} =
             send_request(:get, "/api/agents/v1/whoami")

    assert acting["allowed"] == allowed["paired"]
    assert {200, %{"data" => _checked_in}} = send_request(:get, "/api/agents/v1/me")
  end

  test "the SIWA service's refusal reaches the agent as the SIWA service wrote it" do
    siwa_refuses(409, "request_replayed")

    assert {409,
            %{
              "error" => %{
                "code" => "request_replayed",
                "message" => "This signed request was already used.",
                "hint" => "Sign a fresh request with a new nonce, then send it again."
              }
            }} = send_request(:get, "/api/agents/v1/me")
  end

  @tag :capture_log
  test "a refused site key, an answer for another site, or no answer pairs nothing" do
    siwa_verifies(@wallet, "patchbay")

    assert {503, %{"error" => %{"code" => "siwa_request_failed"}}} =
             send_request(:get, "/api/agents/v1/me")

    siwa_refuses(401, "site_verify_unauthorized")

    assert {503, %{"error" => %{"code" => "siwa_request_failed"}}} =
             send_request(:get, "/api/agents/v1/me")

    Req.Test.stub(RegentAgents.Broker, &Req.Test.transport_error(&1, :econnrefused))

    assert {503, %{"error" => %{"code" => "siwa_request_failed"}}} =
             send_request(:get, "/api/agents/v1/me")
  end

  test "any other request under the mount is not an agent request" do
    assert {404, %{"error" => %{"code" => "not_found"}}} =
             send_request(:get, "/api/agents/v1/pair")
  end
end

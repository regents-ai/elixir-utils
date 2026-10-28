defmodule RegentAgents.HostedPairingTest do
  # A site lists the hosted runtimes whose connection it serves, so switching
  # on Claude does not also offer ChatGPT (27 Oct 2026).
  use RegentAgents.Case, async: false

  import Plug.Test

  alias RegentAgents.Harness

  setup do
    on_exit(fn -> Application.delete_env(:regent_agents, :hosted_pairing) end)
  end

  defp pair(harness) do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      Req.Test.json(conn, %{
        "code" => "http_envelope_valid",
        "data" => %{
          "verified" => true,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => "0x2222222222222222222222222222222222222222",
            "chain_id" => 8453,
            "audience" => "test"
          },
          "agentRegistration" => nil,
          "agentBook" => nil
        }
      })
    end)

    body =
      Jason.encode!(%{"code" => code!(person(harness)), "name" => "App", "harness" => harness})

    conn =
      conn(:post, "/api/agents/v1/pair", body)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> RegentAgents.Test.Router.call(RegentAgents.Test.Router.init([]))

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  test "a site offers only the hosted runtimes it lists" do
    Application.put_env(:regent_agents, :hosted_pairing, [:claude])

    assert Harness.hosted() == [:claude]
    assert :claude in Harness.offered()
    refute :chatgpt in Harness.offered()
    assert :codex in Harness.offered()

    assert {201, %{"data" => %{"harness" => "claude"}}} = pair("claude")
    assert {400, %{"error" => %{"code" => "harness_unknown", "hint" => hint}}} = pair("chatgpt")
    assert hint =~ ~r/\bclaude\b/
    refute hint =~ "chatgpt"
  end

  test "a site that lists none offers every agent but the hosted runtimes" do
    assert Harness.hosted() == []
    assert Harness.offered() == Harness.values() -- Harness.hosted_runtimes()
    assert {400, %{"error" => %{"code" => "harness_unknown"}}} = pair("claude")
  end

  test "a site that lists both offers every agent" do
    Application.put_env(:regent_agents, :hosted_pairing, [:chatgpt, :claude])
    assert Harness.offered() == Harness.values()
  end
end

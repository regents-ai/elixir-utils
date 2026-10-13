defmodule RegentAgents.ActivityTest do
  # Sets the site's audience and reader key for the whole app.
  use ExUnit.Case, async: false

  alias RegentAgents.{Activity, PairedAgent}

  setup do
    siwa = Application.fetch_env!(:regent_agents, :siwa)
    Application.put_env(:regent_agents, :siwa, Keyword.put(siwa, :audience, "ash-template"))
    Application.put_env(:regent_agents, :activity_read_token, "reader")

    on_exit(fn ->
      Application.put_env(:regent_agents, :siwa, siwa)
      Application.delete_env(:regent_agents, :activity_read_token)
    end)
  end

  # Sean 140 a: a read sent as POST to this site showed as a change.
  test "a request to this site is named by its operation, and an unnamed POST is never a change" do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "activity" => [
            request("POST", "/tools/account/credits/history"),
            request("POST", "/tools/notes/9f1/unknown")
          ],
          "next" => "older",
          "agentRegistration" => nil
        }
      })
    end)

    operations = [
      %{
        method: "POST",
        path: "/tools/account/credits/history",
        words: "Read your Credits history"
      }
    ]

    agent = %PairedAgent{wallet: "0x1", paired_at: ~U[2026-10-01 00:00:00Z]}

    assert {:ok, %{entries: [named, unnamed]}} = Activity.recent(agent, operations)
    assert %{site: "Ash Template", action: "Read your Credits history"} = named
    assert unnamed.action == "Sent a request"
  end

  defp request(method, path),
    do: %{
      "audience" => "ash-template",
      "method" => method,
      "path" => path,
      "occurred_at" => "2026-10-13T10:00:00Z"
    }
end

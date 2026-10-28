defmodule RegentAgents.ActivityTest do
  # The SIWA service's answer decides what the account menu shows for an agent; an
  # answer in an unexpected shape once closed the page that asked. Agreed with Sean,
  # 16 Oct 2026, as the one check on how activity is read.
  use ExUnit.Case, async: false

  alias RegentAgents.{Activity, PairedAgent}

  @agent %PairedAgent{
    wallet: "0x2222222222222222222222222222222222222222",
    paired_at: ~U[2026-10-01 00:00:00Z]
  }

  setup do
    Application.put_env(:regent_agents, :activity_read_token, "reader")
    on_exit(fn -> Application.delete_env(:regent_agents, :activity_read_token) end)
  end

  defp siwa_answers(data),
    do: Req.Test.stub(RegentAgents.Broker, &Req.Test.json(&1, %{"data" => data}))

  defp day(audience, day, first, last),
    do: %{"audience" => audience, "day" => day, "first_seen_at" => first, "last_seen_at" => last}

  test "reads Regent days, leaves out other sites, and refuses an unreadable answer" do
    siwa_answers(%{
      "days" => [
        day("patchbay", "2026-10-16", "2026-10-16T09:00:00Z", "2026-10-16T17:30:00Z"),
        day("elsewhere", "2026-10-16", "2026-10-16T10:00:00Z", "2026-10-16T11:00:00Z"),
        day("ash-template", "2026-10-15", "2026-10-15T08:00:00Z", "2026-10-15T08:05:00Z")
      ],
      "agentRegistration" => nil
    })

    assert {:ok, %{days: [patchbay, ash_template], listing: nil} = reading} =
             Activity.recent(@agent)

    assert %{site: "Patchbay", day: ~D[2026-10-16]} = patchbay
    assert ash_template.site == "Ash Template"
    assert Activity.latest(reading) == %{site: "Patchbay", at: ~U[2026-10-16 17:30:00Z]}

    siwa_answers(%{
      "days" => [day("patchbay", "2026-10-16", "", "2026-10-16T17:30:00Z")],
      "agentRegistration" => nil
    })

    assert Activity.recent(@agent) == {:error, :bad_day}

    siwa_answers(%{"days" => nil, "agentRegistration" => nil})
    assert Activity.recent(@agent) == {:error, :bad_days}
  end
end

defmodule RegentCredits.BudgetTest do
  use ExUnit.Case, async: false
  import RegentCredits.Fixtures

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentCredits.TestRepo)
    enabled = Application.fetch_env!(:regent_credits, :agent_grants_enabled)
    on_exit(fn -> Application.put_env(:regent_credits, :agent_grants_enabled, enabled) end)
  end

  test "budget preserves existing grant authority and shared usage through revocation and re-pairing" do
    owner = fund(person(), "0", "10")
    address = wallet()
    episode = pairing(owner, address)
    agent = RegentCredits.Actor.agent(owner, address, "patchbay", episode)

    assert {:error, _} = RegentCredits.agent_budget()
    assert {:error, _} = RegentCredits.agent_budget(actor: actor(owner))
    assert {:error, _} = RegentCredits.agent_budget(actor: %{agent | privy_user_id: person()})
    assert {:error, _} = RegentCredits.agent_budget(actor: %{agent | agent_address: wallet()})

    settings = %{
      privy_user_id: owner,
      agent_address: address,
      enabled: true,
      max_per_spend: d("3"),
      daily_limit: d("5"),
      sites: ["patchbay", "regents"]
    }

    assert {:ok, _} =
             RegentCredits.set_agent_permission(settings,
               actor: RegentCredits.Actor.person(owner, [], "regents")
             )

    assert {:ok, _} = RegentCredits.hold("budget-held", owner, d("2"), "fix", actor: agent)
    Application.put_env(:regent_credits, :agent_grants_enabled, false)

    assert {:ok, budget} = RegentCredits.agent_budget(actor: agent)
    assert budget.enabled and budget.site_allowed
    refute budget.grant_approvals_available
    assert Decimal.eq?(budget.used_24h, 2)
    assert Decimal.eq?(budget.remaining_24h, 3)

    assert {:ok, elsewhere} =
             RegentCredits.agent_budget(actor: %{agent | site: "techtree"})

    assert elsewhere.enabled
    refute elsewhere.site_allowed
    assert Decimal.eq?(elsewhere.used_24h, 2)

    other_address = wallet()
    other_episode = pairing(owner, other_address)
    other = RegentCredits.Actor.agent(owner, other_address, "regents", other_episode)
    assert {:ok, no_grant} = RegentCredits.agent_budget(actor: other)
    refute no_grant.enabled
    assert Decimal.eq?(no_grant.used_24h, 2)
    assert Decimal.eq?(no_grant.remaining_24h, 0)

    person = %RegentAgents.Person{privy_user_id: owner}
    paired = RegentAgents.get_my_agent!(episode, actor: person)
    assert :ok = RegentAgents.unpair_agent(paired, actor: person)
    assert {:error, _} = RegentCredits.agent_budget(actor: agent)

    replacement = pairing(owner, address)
    assert {:ok, fresh} = RegentCredits.agent_budget(actor: %{agent | pairing_id: replacement})
    refute fresh.enabled
    assert fresh.sites == []
    assert Decimal.eq?(fresh.used_24h, 2)

    assert {:ok, _} = RegentCredits.give_back("budget-held", "returned", actor: site())
    assert {:ok, returned} = RegentCredits.agent_budget(actor: other)
    assert Decimal.eq?(returned.used_24h, 0)
  end
end

defmodule RegentCredits.ReferenceSecurityTest do
  use ExUnit.Case, async: false
  import RegentCredits.Fixtures
  require Ash.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentCredits.TestRepo)
  end

  test "purchase details require ownership, while internal server checking remains possible" do
    owner = person()
    p = bought(owner, wallet(), 10)
    assert {:ok, %{id: id}} = RegentCredits.check_purchase(p.id, actor: actor(owner))
    assert id == p.id
    assert {:error, _} = RegentCredits.check_purchase(p.id)
    assert {:error, _} = RegentCredits.check_purchase(p.id, actor: actor(person()))
    assert {:ok, %{id: ^id}} = RegentCredits.check_purchase(p.id, actor: admin())
    assert {:ok, %{id: ^id}} = RegentCredits.Purchases.check(p.id)
  end

  test "self carry cannot trap funds or bypass the agent's daily limit" do
    owner = fund(person(), "0", "5")
    address = wallet()

    pairing_id = pairing(owner, address)

    {:ok, _} =
      RegentCredits.set_agent_permission(
        %{
          privy_user_id: owner,
          agent_address: address,
          enabled: true,
          max_per_spend: d("2"),
          daily_limit: d("2"),
          sites: ["patchbay"]
        },
        actor: RegentCredits.Actor.person(owner, [], "regents")
      )

    agent = RegentCredits.Actor.agent(owner, address, "patchbay", pairing_id)
    {:ok, h} = RegentCredits.hold("self", owner, d("2"), "offer_bid", actor: agent)
    assert {:error, _} = RegentCredits.carry_over("self", "self", "offer_bid", actor: site())
    assert {:error, _} = RegentCredits.hold("second", owner, d("2"), "offer_bid", actor: agent)
    assert Decimal.eq?(RegentCredits.balance(owner).held, 2)

    assert RegentCredits.Hold
           |> Ash.Query.filter(id == ^h.id)
           |> Ash.read_one!(authorize?: false)
           |> Map.fetch!(:status) == :held

    assert {:ok, _} = RegentCredits.give_back("self", "returned", actor: site())
    assert Decimal.eq?(RegentCredits.balance(owner).available, 5)
  end

  test "revocation stops new holds, preserves settlement, and re-pairing cannot revive a grant" do
    grants_enabled = Application.fetch_env!(:regent_credits, :agent_grants_enabled)
    on_exit(fn -> Application.put_env(:regent_credits, :agent_grants_enabled, grants_enabled) end)

    owner = fund(person(), "0", "5")
    address = wallet()
    pairing_id = pairing(owner, address)

    settings = %{
      privy_user_id: owner,
      agent_address: address,
      enabled: true,
      max_per_spend: d("5"),
      daily_limit: d("5"),
      sites: ["patchbay", "regents"]
    }

    Application.delete_env(:regent_credits, :agent_grants_enabled)
    refute RegentCredits.agent_grants_enabled?()

    assert {:error, error} =
             RegentCredits.set_agent_permission(settings,
               actor: RegentCredits.Actor.person(owner, [], "regents"),
               context: %{agent_grants_enabled: true},
               authorize?: false
             )

    assert Exception.message(error) =~
             "Agent spending grants are unavailable until the shared rollout is complete."

    grant_query =
      Ash.Query.filter(RegentCredits.AgentPermission, privy_user_id == ^owner)

    assert [] == Ash.read!(grant_query, authorize?: false)
    Application.put_env(:regent_credits, :agent_grants_enabled, true)
    assert RegentCredits.agent_grants_enabled?()

    assert {:ok, grant} =
             RegentCredits.set_agent_permission(settings,
               actor: RegentCredits.Actor.person(owner, [], "regents")
             )

    assert grant.pairing_id == pairing_id
    agent = RegentCredits.Actor.agent(owner, address, "patchbay", pairing_id)
    assert {:ok, hold} = RegentCredits.hold("before", owner, d("1"), "fix", actor: agent)
    assert hold.pairing_id == pairing_id

    Application.put_env(:regent_credits, :agent_grants_enabled, false)

    person = %RegentAgents.Person{privy_user_id: owner}
    paired = RegentAgents.get_my_agent!(pairing_id, actor: person)
    assert :ok = RegentAgents.unpair_agent(paired, actor: person)

    assert {:error, _} = RegentCredits.hold("after", owner, d("1"), "fix", actor: agent)
    assert {:error, _} = RegentCredits.hold("before", owner, d("1"), "fix", actor: agent)
    assert {:ok, _} = RegentCredits.charge("before", actor: site())

    next = pairing(owner, address)
    next_agent = RegentCredits.Actor.agent(owner, address, "patchbay", next)

    assert {:error, _} =
             RegentCredits.hold("new-episode", owner, d("1"), "fix", actor: next_agent)

    Application.put_env(:regent_credits, :agent_grants_enabled, true)

    assert {:error, _} = RegentCredits.set_agent_permission(settings, actor: next_agent)

    assert {:ok, _} =
             RegentCredits.set_agent_permission(settings,
               actor: RegentCredits.Actor.person(owner, [], "regents")
             )

    assert {:ok, _} = RegentCredits.hold("new-episode", owner, d("1"), "fix", actor: next_agent)

    Application.put_env(:regent_credits, :agent_grants_enabled, false)

    assert {:ok, %{enabled: false}} =
             RegentCredits.set_agent_permission(%{settings | enabled: false},
               actor: RegentCredits.Actor.person(owner, [], "regents")
             )

    assert {:error, _} =
             RegentCredits.set_agent_permission(settings,
               actor: RegentCredits.Actor.person(owner, [], "regents")
             )

    assert %{enabled: false} = Ash.read_one!(grant_query, authorize?: false)
  end

  test "all permanent movements are paged privately, including holds and millionths" do
    owner = fund(person(), "2", "3")
    {:ok, _} = RegentCredits.hold("held", owner, d("4"), "offer_bid", actor: actor(owner))
    {:ok, _} = RegentCredits.give_back("held", "returned", actor: site())

    for n <- 1..55 do
      {:ok, _} = RegentCredits.give("gift-#{n}", [owner], d("0.000001"), actor: admin())
    end

    {:ok, first} = RegentCredits.history(actor: actor(owner))
    assert length(first.entries) == 50 and first.more?
    {:ok, rest} = RegentCredits.history(%{after: first.next}, actor: actor(owner))
    all = first.entries ++ rest.entries
    assert length(all) == 61 and not rest.more?
    assert length(Enum.uniq_by(all, & &1.id)) == 61
    assert Enum.count(all, &Decimal.eq?(&1.available_delta, d("0.000001"))) == 55

    assert Enum.any?(
             all,
             &(Decimal.negative?(&1.available_delta) and Decimal.positive?(&1.held_delta))
           )

    assert Enum.any?(
             all,
             &(Decimal.positive?(&1.available_delta) and Decimal.negative?(&1.held_delta))
           )

    assert {:ok, %{entries: []}} = RegentCredits.history(actor: actor(person()))
    assert {:error, _} = RegentCredits.history()
    assert {:error, _} = RegentCredits.history(actor: site())
    refute Enum.any?(all, &Map.has_key?(&1, :from_account_id))
  end
end

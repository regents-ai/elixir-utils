defmodule RegentCredits.ConcurrencyTest do
  @moduledoc """
  Operations racing each other on real, separate connections. The rows these
  tests write stay in the test database; every test uses its own people.
  """
  use ExUnit.Case, async: false

  import RegentCredits.Fixtures

  alias RegentCredits.{Actor, Ledger, TestRepo}

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual) end)
  end

  defp race(count, fun) do
    1..count
    |> Task.async_stream(fun, max_concurrency: count, timeout: 30_000)
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp ok_count(results), do: Enum.count(results, &match?({:ok, _}, &1))

  test "twenty holds of 1 racing over 5 Credits: exactly five are placed" do
    owner = fund(person(), "2", "3")

    results =
      race(20, fn i ->
        RegentCredits.hold("race-#{owner}-#{i}", owner, d("1"), "fix", actor: actor(owner))
      end)

    assert ok_count(results) == 5
    assert Decimal.eq?(RegentCredits.balance(owner).held, 5)
    assert Decimal.eq?(RegentCredits.balance(owner).available, 0)
  end

  test "a give back and a charge racing on one hold: exactly one closes it" do
    owner = fund(person(), "0", "1")
    key = "fix-#{owner}"
    {:ok, _} = RegentCredits.hold(key, owner, d("1"), "fix", actor: actor(owner))

    results =
      race(10, fn i ->
        if rem(i, 2) == 0,
          do: RegentCredits.charge(key, actor: site()),
          else: RegentCredits.give_back(key, "failed", actor: site())
      end)

    statuses =
      results
      |> Enum.flat_map(fn
        {:ok, hold} -> [hold.status]
        _ -> []
      end)
      |> Enum.uniq()

    assert length(statuses) == 1
    balance = RegentCredits.balance(owner)

    assert Decimal.eq?(
             Decimal.add(balance.available, balance.held),
             if(statuses == [:charged], do: 0, else: 1)
           )
  end

  test "people paying bounties to each other at once never deadlock" do
    a = fund(person(), "0", "100")
    b = fund(person(), "0", "100")

    results =
      race(40, fn i ->
        {from, to} = if rem(i, 2) == 0, do: {a, b}, else: {b, a}
        key = "post-#{from}-#{i}"
        {:ok, _} = RegentCredits.hold(key, from, d("1"), "priority_post", actor: actor(from))
        RegentCredits.pay_bounty(key, to, actor: site())
      end)

    assert ok_count(results) == 40, inspect(Enum.reject(results, &match?({:ok, _}, &1)), limit: 3)
    # Each paid 20 and received 20 x 0.9.
    assert Decimal.eq?(RegentCredits.balance(a).available, d("98"))
    assert Decimal.eq?(RegentCredits.balance(b).available, d("98"))
  end

  test "an agent's held bids count toward its daily limit, and a returned bid gives the room back" do
    owner = fund(person(), "0", "50")
    agent = "0x00000000000000000000000000000000000000a1"

    {:ok, _} =
      RegentCredits.set_agent_permission(
        %{
          privy_user_id: owner,
          agent_address: agent,
          enabled: true,
          max_per_spend: d("3"),
          daily_limit: d("5"),
          sites: ["patchbay"]
        },
        actor: Actor.person(owner, [], "regents")
      )

    as_agent = Actor.agent(owner, agent, "patchbay")

    results =
      race(10, fn i ->
        RegentCredits.hold("agent-#{owner}-#{i}", owner, d("1"), "offer_bid", actor: as_agent)
      end)

    assert ok_count(results) == 5

    {:ok, _} =
      RegentCredits.give_back("agent-#{owner}-#{first_ok(results)}", "lost", actor: site())

    assert {:ok, _} =
             RegentCredits.hold("agent-#{owner}-again", owner, d("1"), "offer_bid",
               actor: as_agent
             )

    assert {:error, _} =
             RegentCredits.hold("agent-#{owner}-over", owner, d("1"), "offer_bid",
               actor: as_agent
             )

    assert {:error, _} =
             RegentCredits.hold("agent-#{owner}-big", owner, d("4"), "offer_bid", actor: as_agent)
  end

  test "ten checks of one landed purchase racing: it credits once" do
    owner = person()
    payer = wallet()
    purchase = report(owner, payer, :base, 30)

    RegentCredits.TestChain.put(
      purchase.tx_hash,
      RegentCredits.TestChain.buy(:base, payer, 30, purchase.number),
      RegentCredits.TestChain.mined("0x1")
    )

    results = race(10, fn _i -> RegentCredits.check_purchase(purchase.id) end)

    assert ok_count(results) == 10
    assert Decimal.eq?(RegentCredits.balance(owner).purchased, 30)
  end

  test "every transfer balances: all accounts together always sum to zero" do
    %{rows: [[total]]} =
      TestRepo.query!("""
      SELECT coalesce(sum((b.balance).amount), 0) FROM regent_credits.accounts a
      JOIN LATERAL (SELECT balance FROM regent_credits.balances
                    WHERE account_id = a.id ORDER BY transfer_id DESC LIMIT 1) b ON true
      """)

    assert Decimal.eq?(total, 0)
    assert [_ | _] = Ledger.balances(["regent_revenue"])
  end

  defp first_ok(results) do
    results
    |> Enum.with_index()
    |> Enum.find_value(fn
      {{:ok, _}, i} -> i + 1
      _ -> nil
    end)
  end
end

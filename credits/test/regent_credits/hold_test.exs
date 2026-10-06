defmodule RegentCredits.HoldTest do
  use ExUnit.Case, async: true

  import RegentCredits.Fixtures

  alias RegentCredits.Errors.{NotEnoughCredits, Refused}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentCredits.TestRepo)
  end

  defp hold(owner, key, amount, actor \\ nil),
    do: RegentCredits.hold(key, owner, d(amount), "offer_bid", actor: actor || actor(owner))

  defp balance(owner) do
    b = RegentCredits.balance(owner)
    Map.new(b, fn {k, v} -> {k, Decimal.to_string(Decimal.normalize(v), :normal)} end)
  end

  defp reason({:error, %Ash.Error.Invalid{errors: [error | _]}}), do: error

  test "a hold takes given Credits first and gives each kind back as it was" do
    owner = fund(person(), "2", "3")
    {:ok, hold} = hold(owner, "bid-1", "4")
    assert {Decimal.to_integer(hold.given), Decimal.to_integer(hold.purchased)} == {2, 2}
    assert balance(owner) == %{available: "1", given: "0", purchased: "1", held: "4"}

    {:ok, back} = RegentCredits.give_back("bid-1", "lost", actor: site())
    assert back.status == :given_back
    assert balance(owner) == %{available: "5", given: "2", purchased: "3", held: "0"}
  end

  test "a hold larger than the available Credits is refused with the shortfall, moving nothing" do
    owner = fund(person(), "1", "0.5")
    assert %NotEnoughCredits{shortfall: shortfall} = reason(hold(owner, key(), "2"))
    assert Decimal.eq?(shortfall, d("0.5"))
    assert balance(owner).held == "0"
  end

  test "repeating a hold answers with the first; the same key with other details is refused" do
    owner = fund(person(), "0", "5")
    {:ok, first} = hold(owner, "bid-2", "1")
    {:ok, again} = hold(owner, "bid-2", "1")
    assert again.id == first.id
    assert %Refused{reason: :key_reused} = reason(hold(owner, "bid-2", "2"))
    assert balance(owner).held == "1"
  end

  test "a person can only hold their own Credits" do
    owner = fund(person(), "0", "5")
    assert {:error, %Ash.Error.Forbidden{}} = hold(owner, key(), "1", actor(person()))
  end

  test "a hold closes once: a second, different close is refused and moves nothing" do
    owner = fund(person(), "0", "5")
    {:ok, _} = hold(owner, "fix-1", "0.10")
    {:ok, charged} = RegentCredits.charge("fix-1", actor: site())
    assert charged.status == :charged
    assert {:ok, %{status: :charged}} = RegentCredits.charge("fix-1", actor: site())

    assert %Refused{reason: :closed} =
             reason(RegentCredits.give_back("fix-1", "failed", actor: site()))

    assert balance(owner) == %{available: "4.9", given: "0", purchased: "4.9", held: "0"}
  end

  test "settle returns the unused share, purchased first, and refuses figures that do not add up" do
    owner = fund(person(), "10", "20")
    {:ok, _} = hold(owner, "offer-1", "30")

    assert %Refused{reason: :split_mismatch} =
             reason(RegentCredits.settle("offer-1", d("20"), d("5"), d("4"), actor: site()))

    # These add up to 30, but the ledger keeps nothing finer than a millionth.
    assert %Refused{reason: :split_mismatch} =
             reason(
               RegentCredits.settle("offer-1", d("19.9999995"), d("10.0000005"), d("0"),
                 actor: site()
               )
             )

    assert balance(owner).held == "30"

    {:ok, settled} = RegentCredits.settle("offer-1", d("20"), d("10"), d("0"), actor: site())
    assert settled.status == :settled
    # The 10 used came from the given Credits; the 20 back are purchased.
    assert balance(owner) == %{available: "20", given: "0", purchased: "20", held: "0"}
  end

  test "carry over keeps the same Credits held under the new key, with no new charge" do
    owner = fund(person(), "0", "5")
    {:ok, _} = hold(owner, "next-1", "3")
    {:ok, carried} = RegentCredits.carry_over("next-1", "offer-2", "offer_bid", actor: site())
    assert carried.key == "offer-2" and carried.status == :held

    assert {:ok, %{id: same}} =
             RegentCredits.carry_over("next-1", "offer-2", "offer_bid", actor: site())

    assert same == carried.id
    assert balance(owner) == %{available: "2", given: "0", purchased: "2", held: "3"}
  end

  test "an agent's bid carried over days later uses its daily room once, on the day it was held" do
    owner = fund(person(), "0", "20")
    agent = "0x00000000000000000000000000000000000000b2"

    {:ok, _} =
      RegentCredits.set_agent_permission(
        %{
          privy_user_id: owner,
          agent_address: agent,
          enabled: true,
          max_per_spend: d("5"),
          daily_limit: d("5"),
          sites: ["patchbay"]
        },
        actor: RegentCredits.Actor.person(owner, [], "regents")
      )

    as_agent = RegentCredits.Actor.agent(owner, agent, "patchbay")
    {:ok, first} = hold(owner, "pre-bid", "3", as_agent)

    # Test only: the library never rewrites a hold's time; this stands in for two days passing.
    RegentCredits.TestRepo.query!(
      "UPDATE regent_credits.holds SET held_at = held_at - interval '2 days' WHERE id = $1",
      [Ecto.UUID.dump!(first.id)]
    )

    {:ok, carried} = RegentCredits.carry_over("pre-bid", "placement", "offer_bid", actor: site())
    assert DateTime.diff(DateTime.utc_now(), carried.held_at, :hour) >= 47

    assert {:ok, _} = hold(owner, "today", "5", as_agent)
    assert %Refused{reason: :agent_daily_limit} = reason(hold(owner, "over", "1", as_agent))
  end

  test "carry over onto a key already in use is refused and leaves the first hold open" do
    owner = fund(person(), "0", "5")
    {:ok, _} = hold(owner, "next-2", "3")
    {:ok, _} = hold(owner, "offer-3", "1")

    assert %Refused{reason: :key_reused} =
             reason(RegentCredits.carry_over("next-2", "offer-3", "offer_bid", actor: site()))

    {:ok, back} = RegentCredits.give_back("next-2", "outbid", actor: site())
    assert back.status == :given_back
    assert balance(owner) == %{available: "4", given: "0", purchased: "4", held: "1"}
  end

  test "a bounty pays 90% to the answer's owner as given Credits and 10% to revenue" do
    asker = fund(person(), "0", "10")
    answerer = person()
    {:ok, _} = hold(asker, "post-1", "10")
    {:ok, paid} = RegentCredits.pay_bounty("post-1", answerer, actor: site())
    assert paid.paid_to == answerer
    assert balance(answerer) == %{available: "9", given: "9", purchased: "0", held: "0"}
    assert balance(asker).available == "0"
  end

  test "a bounty for an unlinked agent waits under its wallet address" do
    asker = fund(person(), "0", "1")
    {:ok, _} = hold(asker, "post-2", "1")

    {:ok, _} =
      RegentCredits.pay_bounty("post-2", "0xAbC0000000000000000000000000000000000001",
        actor: site()
      )

    [waiting] =
      RegentCredits.Ledger.balances([
        RegentCredits.Ledger.identifier(
          :address_given,
          "0xabc0000000000000000000000000000000000001"
        )
      ])

    assert Decimal.eq?(waiting, d("0.9"))
  end

  test "a bounty for a wallet an account holds is paid to that account" do
    asker = fund(person(), "0", "1")
    answerer = person()
    address = wallet()
    {:ok, _moved} = RegentCredits.attach_wallets(answerer, [address], actor: site())
    {:ok, _} = hold(asker, "post-3", "1")

    {:ok, _} = RegentCredits.pay_bounty("post-3", address, actor: site())
    assert balance(answerer).given == "0.9"
  end

  test "an unanswered bounty comes back to the asker at 90%, as given Credits" do
    asker = fund(person(), "0", "10")
    {:ok, _} = hold(asker, "post-3", "10")
    {:ok, _} = RegentCredits.take_back("post-3", actor: site())
    assert balance(asker) == %{available: "9", given: "9", purchased: "0", held: "0"}
  end

  test "only the site that placed a hold can close it" do
    owner = fund(person(), "0", "1")
    {:ok, _} = hold(owner, "fix-2", "0.1")
    other = RegentCredits.Actor.site("techtree")
    assert %Refused{reason: :not_found} = reason(RegentCredits.charge("fix-2", actor: other))
    assert {:error, %Ash.Error.Forbidden{}} = RegentCredits.charge("fix-2", actor: actor(owner))
  end

  test "transfers can never be changed or removed" do
    owner = fund(person(), "0", "1")
    {:ok, _} = hold(owner, key(), "1")

    assert_raise Postgrex.Error, ~r/rows are final/, fn ->
      RegentCredits.TestRepo.query!("UPDATE regent_credits.transfers SET operation = 'x'")
    end
  end
end

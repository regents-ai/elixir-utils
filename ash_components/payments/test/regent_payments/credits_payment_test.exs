defmodule RegentPayments.CreditsPaymentTest do
  @moduledoc """
  Paying an intent in Regent Credits instead of USDC. The price is spent from
  the payer's Credits at one Credit per USDC, in the transaction that settles
  the intent, and only once however often it is pressed. A refused spend
  takes nothing and leaves the intent payable. No facilitator is involved, so
  none is started.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias RegentCredits.Actor
  alias RegentCredits.Ledger
  alias RegentPayments.Purchase
  alias RegentPayments.Test.Actor, as: Payer
  alias RegentPayments.Test.AgentActor
  alias RegentPayments.Test.DirectOffer
  alias RegentPayments.Test.Effects
  alias RegentPayments.TestRepo

  setup do
    :ok = Sandbox.checkout(TestRepo)
    Sandbox.mode(TestRepo, {:shared, self()})
    owner = "did:privy:" <> Ecto.UUID.generate()
    payer = %Payer{id: Ecto.UUID.generate(), wallet_address: wallet()}
    %{owner: owner, payer: payer, person: Actor.person(owner, [], "test")}
  end

  test "a person's Credits pay the price once, and the effect is carried out once", c do
    fund(c.owner, "1", "4")
    intent = prepare(c.payer, 2_500_000)

    assert {:applied, applied, receipt} =
             Purchase.pay_with_credits(c.payer, intent.id, c.person, %{})

    assert applied.status == :applied
    assert receipt.paid_with == :credits
    assert receipt.amount_atomic == 2_500_000
    assert receipt.payer_address == nil
    assert Effects.carried_out(intent.id) == 1
    assert Decimal.eq?(available(c.owner), "2.500000")

    assert {:applied, _, _} = Purchase.pay_with_credits(c.payer, intent.id, c.person, %{})
    assert Effects.carried_out(intent.id) == 1
    assert Decimal.eq?(available(c.owner), "2.500000")
  end

  test "Credits that fall short spend nothing and leave the intent payable", c do
    fund(c.owner, "0", "1")
    intent = prepare(c.payer, 2_000_000)

    assert {:credits_refused, _, "Not enough Credits: 1.00 Credits short."} =
             Purchase.pay_with_credits(c.payer, intent.id, c.person, %{})

    assert Decimal.eq?(available(c.owner), 1)
    assert {:ok, %{status: :prepared, receipt: nil}} = Purchase.read(c.payer, intent.id)
  end

  test "terms that refuse Credits cannot be paid with them", c do
    fund(c.owner, "0", "5")
    intent = prepare(c.payer, 1_000_000, :refused)

    assert {:credits_refused, _, "This payment can't be paid with Credits."} =
             Purchase.pay_with_credits(c.payer, intent.id, c.person, %{})

    assert Decimal.eq?(available(c.owner), 5)
  end

  test "an agent spends its person's Credits only as itself, within their limits", c do
    fund(c.owner, "0", "10")
    agent = paired_agent(c.owner)
    permit(c.owner, agent.wallet_address, "1")
    as_agent = Actor.agent(c.owner, agent.wallet_address, "test", agent.pairing_id)

    over = prepare(agent, 2_000_000)

    assert {:credits_refused, _, "This is more than your person lets you spend at once."} =
             Purchase.pay_with_credits(agent, over.id, as_agent, %{})

    intent = prepare(agent, 1_000_000)
    other_pairing = %{as_agent | pairing_id: Ecto.UUID.generate()}
    assert {:error, _} = Purchase.pay_with_credits(agent, intent.id, other_pairing, %{})
    assert {:error, _} = Purchase.pay_with_credits(agent, intent.id, c.person, %{})

    assert {:applied, _, %{paid_with: :credits}} =
             Purchase.pay_with_credits(agent, intent.id, as_agent, %{})

    assert Decimal.eq?(available(c.owner), 9)
  end

  defp prepare(payer, amount, credits \\ :accepted) do
    {:ok, intent} =
      RegentPayments.prepare_payment_intent(
        DirectOffer,
        %{
          amount_atomic: amount,
          pay_to: "0x" <> String.duplicate("b", 40),
          target_id: Ecto.UUID.generate(),
          credits: credits
        },
        actor: payer
      )

    intent
  end

  defp paired_agent(owner) do
    id = Ecto.UUID.generate()

    agent = %AgentActor{
      id: id,
      acting_agent_id: id,
      wallet_address: wallet(),
      privy_user_id: owner,
      beneficiary_profile_id: Ecto.UUID.generate(),
      human_account_id: 1,
      pairing_id: Ecto.UUID.generate()
    }

    TestRepo.query!(
      "INSERT INTO regent_agents.paired_agents (id,privy_user_id,wallet,name,harness,paired_at,last_contact_at) VALUES ($1,$2,$3,'fixture','fixture',now(),now())",
      [Ecto.UUID.dump!(agent.pairing_id), owner, agent.wallet_address]
    )

    agent
  end

  defp permit(owner, agent_address, max_per_spend) do
    {:ok, _} =
      RegentCredits.set_agent_permission(
        %{
          privy_user_id: owner,
          agent_address: agent_address,
          enabled: true,
          max_per_spend: Decimal.new(max_per_spend),
          daily_limit: Decimal.new(5),
          sites: ["test"]
        },
        actor: Actor.person(owner, [], "regents")
      )
  end

  defp fund(owner, given, purchased) do
    Ledger.open(Ledger.person(owner))
    given_to = Ledger.identifier(:given, owner)
    purchased_to = Ledger.identifier(:purchased, owner)

    TestRepo.transaction(fn ->
      ["regent_gifts", "regent_purchases", given_to, purchased_to]
      |> Ledger.lock()
      |> Ledger.move({"regent_gifts", given_to}, Decimal.new(given), "gift:fund")
      |> Ledger.move(
        {"regent_purchases", purchased_to},
        Decimal.new(purchased),
        "purchase:#{Ecto.UUID.generate()}"
      )
    end)
  end

  defp available(owner) do
    accounts = owner |> Ledger.person() |> Ledger.lock()

    Decimal.add(
      Ledger.balance_of(accounts, Ledger.identifier(:given, owner)),
      Ledger.balance_of(accounts, Ledger.identifier(:purchased, owner))
    )
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end

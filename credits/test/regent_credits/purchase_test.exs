defmodule RegentCredits.PurchaseTest do
  use ExUnit.Case, async: true

  import RegentCredits.Fixtures

  alias RegentCredits.Errors.Refused
  alias RegentCredits.TestChain

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentCredits.TestRepo)
  end

  defp purchased(owner), do: RegentCredits.balance(owner).purchased |> Decimal.to_integer()
  defp check(purchase), do: RegentCredits.check_purchase!(purchase.id)

  test "a Base purchase credits once when its deposit lands, however often it is checked or reported" do
    owner = person()
    payer = wallet()
    purchase = report(owner, payer, :base, 25)
    assert check(purchase).status == :checking

    TestChain.put(
      purchase.tx_hash,
      TestChain.buy(:base, payer, 25, purchase.number),
      TestChain.mined("0x1")
    )

    assert check(purchase).status == :credited
    assert check(purchase).status == :credited

    {:ok, again} =
      RegentCredits.report_purchase(owner, payer, :base, 25, purchase.number, purchase.tx_hash,
        actor: actor(owner, [payer])
      )

    assert again.id == purchase.id
    assert purchased(owner) == 25
  end

  test "only an account holding the paying wallet can claim a payment, and it credits once" do
    owner = person()
    payer = wallet()
    purchase = report(owner, payer, :base, 10)

    TestChain.put(
      purchase.tx_hash,
      TestChain.buy(:base, payer, 10, purchase.number),
      TestChain.mined("0x1")
    )

    other = person()

    claim =
      &RegentCredits.report_purchase(other, payer, :base, 10, purchase.number, purchase.tx_hash,
        actor: &1
      )

    assert {:error, %Ash.Error.Forbidden{}} = claim.(actor(other, [wallet()]))

    # Were two accounts ever both to hold the wallet, the second ends instead of waiting forever.
    {:ok, copy} = claim.(actor(other, [payer]))
    assert check(purchase).status == :credited
    assert %{status: :failed, reason: "already credited"} = check(copy)
    assert {purchased(owner), purchased(other)} == {10, 0}
  end

  # A made-up hash must never become a saved purchase the site re-checks for a day.
  test "a report is saved only once the chain holds it as this purchase from this wallet" do
    owner = person()
    payer = wallet()
    number = Ecto.UUID.generate()
    hash = TestChain.hash()

    report = fn ->
      RegentCredits.report_purchase(owner, payer, :base, 25, number, hash,
        actor: actor(owner, [payer])
      )
    end

    assert {:error, %Ash.Error.Invalid{errors: [%Refused{reason: :not_seen_yet}]}} = report.()

    TestChain.put(hash, TestChain.buy(:base, wallet(), 25, number), nil)

    assert {:error, %Ash.Error.Invalid{errors: [%Refused{reason: :not_this_purchase}]}} =
             report.()

    assert RegentCredits.purchases!(actor: actor(owner)) == []

    TestChain.put(hash, TestChain.buy(:base, payer, 25, number), nil)
    assert {:ok, %{status: :checking}} = report.()
  end

  test "the site's Oban finds an open purchase with nobody signed in and credits it" do
    owner = person()
    payer = wallet()
    purchase = report(owner, payer, :base, 15)

    TestChain.put(
      purchase.tx_hash,
      TestChain.buy(:base, payer, 15, purchase.number),
      TestChain.mined("0x1")
    )

    AshOban.Test.schedule_and_run_triggers(RegentCredits.Purchase)
    assert purchased(owner) == 15
  end

  test "a reverted purchase never credits" do
    owner = person()
    payer = wallet()
    purchase = report(owner, payer, :base, 5)

    TestChain.put(
      purchase.tx_hash,
      TestChain.buy(:base, payer, 5, purchase.number),
      TestChain.mined("0x0")
    )

    assert %{status: :failed, reason: "reverted"} = check(purchase)
    assert purchased(owner) == 0
  end

  test "an Ethereum purchase credits after 12 blocks on top, starting over when its block changes" do
    owner = person()
    payer = wallet()
    purchase = report(owner, payer, :ethereum, 20)
    tx = TestChain.buy(:ethereum, payer, 20, purchase.number)

    TestChain.put(purchase.tx_hash, tx, TestChain.mined("0x1", 100))
    TestChain.head(105)
    assert %{status: :checking, block_number: 100} = check(purchase)

    # A reorg moved it to block 101; 112 is only 11 blocks on top of that.
    TestChain.put(purchase.tx_hash, tx, TestChain.mined("0x1", 101))
    TestChain.head(112)
    assert %{status: :checking, block_number: 101} = check(purchase)
    assert check(purchase).status == :checking

    TestChain.head(113)
    assert check(purchase).status == :credited
    assert purchased(owner) == 20
  end
end

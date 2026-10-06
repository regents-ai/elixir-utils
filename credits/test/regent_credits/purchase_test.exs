defmodule RegentCredits.PurchaseTest do
  use ExUnit.Case, async: true

  import RegentCredits.Fixtures

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
        actor: actor(owner)
      )

    assert again.id == purchase.id
    assert purchased(owner) == 25
  end

  test "someone else reporting a person's transaction gets nothing and blocks nothing" do
    owner = person()
    payer = wallet()
    purchase = report(owner, payer, :base, 10)

    TestChain.put(
      purchase.tx_hash,
      TestChain.buy(:base, payer, 10, purchase.number),
      TestChain.mined("0x1")
    )

    other = person()

    {:ok, copy} =
      RegentCredits.report_purchase(other, wallet(), :base, 10, purchase.number, purchase.tx_hash,
        actor: actor(other)
      )

    assert %{status: :failed, reason: "not this purchase"} = check(copy)
    assert check(purchase).status == :credited
    assert {purchased(owner), purchased(other)} == {10, 0}
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

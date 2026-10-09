defmodule RegentCredits.GiftRefundTest do
  use ExUnit.Case, async: true

  import RegentCredits.Fixtures

  alias RegentCredits.{Chains, TestChain}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentCredits.TestRepo)
  end

  defp reason({:error, %Ash.Error.Invalid{errors: [error | _]}}), do: error.reason
  defp given(owner), do: RegentCredits.balance(owner).given |> Decimal.to_integer()

  test "a gift is given once per send; a gift to an address waits until that wallet is attached" do
    owner = person()
    address = wallet()
    key = key()

    {:ok, _gifts} = RegentCredits.give(key, [owner, address], d(3), actor: admin())
    {:ok, gifts} = RegentCredits.give(key, [owner, address], d(3), actor: admin())
    assert length(gifts) == 2
    assert given(owner) == 3

    newcomer = person()
    assert {:ok, moved} = RegentCredits.attach_wallets(newcomer, [address], actor: site())
    assert Decimal.eq?(moved, 3)
    assert {:ok, moved} = RegentCredits.attach_wallets(newcomer, [address], actor: site())
    assert Decimal.eq?(moved, 0)
    assert given(newcomer) == 3

    assert {:error, %Ash.Error.Forbidden{}} =
             RegentCredits.give(key(), [owner], d(1), actor: actor(owner))
  end

  test "a gift to a wallet an account holds lands at once, and waits again once the account drops it" do
    owner = person()
    address = wallet()
    {:ok, _moved} = RegentCredits.attach_wallets(owner, [address], actor: site())

    {:ok, _gifts} = RegentCredits.give(key(), [address], d(2), actor: admin())
    assert given(owner) == 2

    {:ok, _moved} = RegentCredits.attach_wallets(owner, [], actor: site())
    {:ok, _gifts} = RegentCredits.give(key(), [address], d(1), actor: admin())
    assert given(owner) == 2

    assert {:ok, moved} = RegentCredits.attach_wallets(owner, [address], actor: site())
    assert Decimal.eq?(moved, 1)
  end

  test "a purchase is refunded only while the account has never used Credits, even a hold given back" do
    owner = person()
    purchase = bought(owner, wallet(), 25)

    {:ok, refund} = RegentCredits.start_refund(purchase.id, actor: admin())
    assert {refund.status, refund.wallet} == {:locked, purchase.wallet}
    assert Decimal.eq?(refund.amount, 25)
    assert {:ok, %{id: same}} = RegentCredits.start_refund(purchase.id, actor: admin())
    assert same == refund.id
    assert RegentCredits.balance(owner).purchased |> Decimal.eq?(0)

    user = person()
    used = bought(user, wallet(), 5)
    bid = key()
    {:ok, _hold} = RegentCredits.hold(bid, user, d(1), "fix", actor: actor(user))
    {:ok, _back} = RegentCredits.give_back(bid, "lost", actor: site())

    assert reason(RegentCredits.start_refund(used.id, actor: admin())) == :used
  end

  test "a refund closes only on the Treasury Safe's exact USDC transfer to the wallet that paid" do
    owner = person()
    payer = wallet()
    purchase = bought(owner, payer, 7)
    {:ok, refund} = RegentCredits.start_refund(purchase.id, actor: admin())

    short = TestChain.hash()
    log = TestChain.transfer_log(:base, Chains.treasury(), payer, Chains.micro(7) - 1)
    TestChain.put(short, %{}, TestChain.mined("0x1", 1, TestChain.hash(), [log]))

    assert reason(RegentCredits.close_refund(refund.id, short, actor: admin())) ==
             :refund_not_proven

    exact = TestChain.hash()
    log = TestChain.transfer_log(:base, Chains.treasury(), payer, Chains.micro(7))
    TestChain.put(exact, %{}, TestChain.mined("0x1", 1, TestChain.hash(), [log]))
    assert {:ok, %{status: :sent}} = RegentCredits.close_refund(refund.id, exact, actor: admin())
    assert {:ok, %{status: :sent}} = RegentCredits.close_refund(refund.id, exact, actor: admin())
    assert reason(RegentCredits.close_refund(refund.id, short, actor: admin())) == :closed
  end
end

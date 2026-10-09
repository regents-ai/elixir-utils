defmodule RegentCredits.DepositTest do
  # Base has one deposit cursor, which every test here moves.
  use ExUnit.Case, async: false

  import RegentCredits.Fixtures

  require Ash.Query

  alias RegentCredits.{Deposits, DepositCursor, TestChain}

  @start 52_227_727

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentCredits.TestRepo)
    TestChain.logs([])
    :ok
  end

  defp read(head) do
    TestChain.head(:base, head)
    Deposits.read(:base)
  end

  defp read_again_from_start do
    cursor = Ash.get!(DepositCursor, :base, authorize?: false)

    cursor
    |> Ash.Changeset.for_update(:advance, %{from: cursor.next_block, to: @start},
      authorize?: false
    )
    |> Ash.update!()
  end

  defp purchased(owner), do: RegentCredits.balance(owner).purchased
  defp purchases(query), do: RegentCredits.purchases!(query: query, authorize?: false)

  defp tag(name),
    do: "0x" <> Base.encode16(String.pad_trailing(name, 32, <<0>>), case: :lower)

  # Why the reader exists: a paid Buy whose page closed before it reported.
  test "every Credits deposit is credited once, exactly as it landed, to the account holding its wallet" do
    owner = person()
    payer = wallet()
    {:ok, _moved} = RegentCredits.attach_wallets(owner, [payer], actor: site())

    TestChain.logs([
      TestChain.deposit_log(payer, 25_000_000, @start + 3),
      TestChain.deposit_log(payer, 3_500_000, @start + 1_200),
      TestChain.deposit_log(payer, 9_000_000, @start + 5, tag: tag("another.app"))
    ])

    assert :ok = read(@start + 2_000)
    assert Decimal.eq?(purchased(owner), "28.5")
    assert_received {:credited, _first, true}
    assert_received {:credited, _second, true}

    # The newest 300 blocks wait for a later read.
    TestChain.logs([TestChain.deposit_log(payer, 5_000_000, @start + 1_995)])
    assert :ok = read(@start + 2_294)
    assert Decimal.eq?(purchased(owner), "28.5")
    assert :ok = read(@start + 2_295)
    assert Decimal.eq?(purchased(owner), "33.5")
    assert_received {:credited, _third, true}

    read_again_from_start()
    assert :ok = read(@start + 2_295)
    assert Decimal.eq?(purchased(owner), "33.5")
    refute_received {:credited, _, _}
  end

  test "a deposit and the page's report of it credit once between them, whichever comes first" do
    owner = person()
    payer = wallet()
    {:ok, _moved} = RegentCredits.attach_wallets(owner, [payer], actor: site())

    reported = report(owner, payer, :base, 25)

    TestChain.logs([
      TestChain.deposit_log(payer, 25_000_000, @start + 1,
        tx_hash: reported.tx_hash,
        number: reported.number
      )
    ])

    assert :ok = read(@start + 400)

    assert RegentCredits.check_purchase!(reported.id,
             actor: actor(reported.privy_user_id, [reported.wallet])
           ).status == :credited

    credited = bought(owner, payer, 10)

    TestChain.logs([
      TestChain.deposit_log(payer, 10_000_000, @start + 120,
        tx_hash: credited.tx_hash,
        number: credited.number
      )
    ])

    assert :ok = read(@start + 500)
    assert Decimal.eq?(purchased(owner), 35)

    assert length(purchases(Ash.Query.filter(RegentCredits.Purchase, privy_user_id == ^owner))) ==
             2
  end

  # A contract can deposit for two wallets in one transaction; each wallet's
  # account gets its own part, once, and its report finds that part.
  test "two wallets paying in one transaction are credited separately, once each" do
    first = person()
    a = wallet()
    b = wallet()
    {:ok, _moved} = RegentCredits.attach_wallets(first, [a], actor: site())
    hash = TestChain.hash()
    number = Ecto.UUID.generate()

    TestChain.logs([
      TestChain.deposit_log(a, 5_000_000, @start + 1, tx_hash: hash, number: number),
      TestChain.deposit_log(b, 25_000_000, @start + 1, tx_hash: hash),
      TestChain.deposit_log(b, 1_500_000, @start + 1, tx_hash: hash)
    ])

    assert :ok = read(@start + 400)
    read_again_from_start()
    assert :ok = read(@start + 400)

    assert Decimal.eq?(purchased(first), 5)
    assert_received {:credited, _a, true}
    refute_received {:credited, _, _}

    TestChain.put(hash, TestChain.buy(:base, a, 5, number), TestChain.mined("0x1"))

    assert {:ok, %{status: :credited, wallet: ^a}} =
             RegentCredits.report_purchase(first, a, :base, 5, number, hash,
               actor: actor(first, [a])
             )

    second = person()
    assert {:ok, moved} = RegentCredits.attach_wallets(second, [b], actor: site())
    assert Decimal.eq?(moved, "26.5")
    assert Decimal.eq?(purchased(first), 5)
    assert length(purchases(Ash.Query.filter(RegentCredits.Purchase, tx_hash == ^hash))) == 2
  end

  # A person reports a Buy from a wallet their account has not attached yet;
  # one record of the payment reaches them in either order, and signing in
  # with the wallet afterwards still works.
  test "a report from a wallet no account holds yet gets the deposit, whichever comes first" do
    reporter = person()
    payer = wallet()
    reported = report(reporter, payer, :base, 25)

    TestChain.logs([
      TestChain.deposit_log(payer, 25_000_000, @start + 1,
        tx_hash: reported.tx_hash,
        number: reported.number
      )
    ])

    assert :ok = read(@start + 400)

    assert RegentCredits.check_purchase!(reported.id,
             actor: actor(reported.privy_user_id, [reported.wallet])
           ).status == :credited

    assert Decimal.eq?(purchased(reporter), 25)
    assert_received {:credited, id, true}
    assert id == reported.id

    late = person()
    number = Ecto.UUID.generate()
    hash = TestChain.hash()

    TestChain.logs([
      TestChain.deposit_log(payer, 10_000_000, @start + 500, tx_hash: hash, number: number)
    ])

    assert :ok = read(@start + 900)
    refute_received {:credited, _, _}

    TestChain.put(hash, TestChain.buy(:base, payer, 10, number), TestChain.mined("0x1"))

    assert {:ok, %{status: :credited, privy_user_id: ^late} = taken} =
             RegentCredits.report_purchase(late, payer, :base, 10, number, hash,
               actor: actor(late, [payer])
             )

    assert Decimal.eq?(purchased(late), 10)
    assert_received {:credited, taken_id, true}
    assert taken_id == taken.id

    assert {:ok, moved} = RegentCredits.attach_wallets(late, [payer], actor: site())
    assert Decimal.eq?(moved, 0)
    assert {:ok, _moved} = RegentCredits.attach_wallets(reporter, [payer], actor: site())
    assert length(purchases(Ash.Query.filter(RegentCredits.Purchase, wallet == ^payer))) == 2
  end

  test "a deposit from a wallet no account holds waits under it, and goes to the account that signs in with it" do
    stranger = wallet()
    TestChain.logs([TestChain.deposit_log(stranger, 40_000_000, @start + 1)])

    assert :ok = read(@start + 400)
    refute_received {:credited, _, _}

    [waiting] = purchases(Ash.Query.filter(RegentCredits.Purchase, wallet == ^stranger))

    assert {:error, %Ash.Error.Invalid{errors: [%{reason: :no_account}]}} =
             RegentCredits.start_refund(waiting.id, actor: admin())

    owner = person()
    assert {:ok, moved} = RegentCredits.attach_wallets(owner, [stranger], actor: site())
    assert Decimal.eq?(moved, 40)
    assert Decimal.eq?(purchased(owner), 40)
    assert_received {:credited, id, true}

    assert [%{id: ^id, privy_user_id: ^owner, status: :credited}] =
             purchases(Ash.Query.filter(RegentCredits.Purchase, wallet == ^stranger))
  end
end

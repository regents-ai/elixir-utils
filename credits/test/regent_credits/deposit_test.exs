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

    # The newest ten blocks wait for a later read.
    TestChain.logs([TestChain.deposit_log(payer, 5_000_000, @start + 1_995)])
    assert :ok = read(@start + 2_000)
    assert Decimal.eq?(purchased(owner), "28.5")
    assert :ok = read(@start + 2_010)
    assert Decimal.eq?(purchased(owner), "33.5")
    assert_received {:credited, _third, true}

    read_again_from_start()
    assert :ok = read(@start + 2_010)
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

    assert :ok = read(@start + 100)
    assert RegentCredits.check_purchase!(reported.id).status == :credited

    credited = bought(owner, payer, 10)

    TestChain.logs([
      TestChain.deposit_log(payer, 10_000_000, @start + 120,
        tx_hash: credited.tx_hash,
        number: credited.number
      )
    ])

    assert :ok = read(@start + 200)
    assert Decimal.eq?(purchased(owner), 35)

    assert length(purchases(Ash.Query.filter(RegentCredits.Purchase, privy_user_id == ^owner))) ==
             2
  end

  test "a deposit from a wallet no account holds waits under it, and goes to the account that signs in with it" do
    stranger = wallet()
    TestChain.logs([TestChain.deposit_log(stranger, 40_000_000, @start + 1)])

    assert :ok = read(@start + 100)
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

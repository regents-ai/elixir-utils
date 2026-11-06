defmodule RegentPoints.SpendingTest do
  # Dollar points: one point per dollar a payment proves, at most 100 dollars an
  # account a UTC day, each payment paid once. Payments are recorded the way a site
  # records them, on a real database, with Oban running each job as it is queued.
  use ExUnit.Case, async: false
  use ExUnitProperties
  require Ash.Query
  alias RegentPoints.{CapUsage, Entry, Event, Rules, Store}

  defmodule Source do
    @moduledoc false
    def verify(%{"source_event_key" => key}),
      do: Map.fetch(Application.get_env(:regent_points, :test_facts, %{}), key)
  end

  defmodule People do
    @moduledoc false
    @behaviour RegentPoints.Accounts

    @impl true
    def human(_id), do: %{wallet_address: nil, wallet_addresses: []}

    @impl true
    def agent_names(_id, _ids), do: {:ok, %{}}

    @impl true
    def people(ids), do: {:ok, Map.new(ids, &{&1, %{name: nil, wallet: nil}})}
  end

  @spending ~w(keyfleet.key_spend patchbay.payment_spend template.pinned_note_spend autolaunch.auction_bid_spend)
  @rules ["patchbay.reply_published" | @spending]
  @start DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -5 * 86_400)
  # A UTC midnight two days ago: payments on either side of it fall on two days.
  @midnight DateTime.new!(Date.add(Date.utc_today(), -2), ~T[00:00:00])
  @limit 100_000_000
  @ceiling 1_000_000_000_000_000

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentPoints.Repo)
    keys = [:program_id, :starts_at, :approved_rules, :adapters, :accounts, :test_facts]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    Application.put_env(:regent_points, :program_id, "spending-test")
    Application.put_env(:regent_points, :starts_at, @start)
    Application.put_env(:regent_points, :approved_rules, @rules)
    Application.put_env(:regent_points, :adapters, Map.new(@rules, &{&1, Source}))
    Application.put_env(:regent_points, :accounts, People)
    :ok
  end

  property "one day's payments across rules and sites earn their dollars until 100, then the rest of that day earns nothing" do
    check all(
            payments <-
              list_of({member_of(@spending), integer(1..150_000_000)},
                min_length: 1,
                max_length: 6
              ),
            max_runs: 12
          ) do
      account = person()
      # The fixed points of an action count under their own limit, not the dollars'.
      report("patchbay.reply_published", account, @midnight, %{})

      for {rule, usd} <- payments, do: pay(rule, account, @midnight, usd)

      expected = clip(Enum.map(payments, &elem(&1, 1)))
      assert Enum.map(spent(account), & &1.points_micro_delta) == expected
      assert Enum.sum(expected) == min(@limit, Enum.sum(Enum.map(payments, &elem(&1, 1))))
    end
  end

  # The site checks a payment some time after its block; the block's day decides.
  property "a payment counts on the UTC day of its block, not the day the site checked it" do
    check all(
            payments <-
              list_of({integer(-7_200..7_199), integer(1..150_000_000)},
                min_length: 1,
                max_length: 6
              ),
            max_runs: 12
          ) do
      account = person()
      checked = DateTime.utc_now()
      at = fn offset -> DateTime.add(@midnight, offset) end

      for {offset, usd} <- payments,
          do: pay("keyfleet.key_spend", account, at.(offset), usd, qualified_at: checked)

      {expected, _room} =
        Enum.map_reduce(payments, %{}, fn {offset, usd}, room ->
          day = DateTime.to_date(at.(offset))
          left = Map.get(room, day, @limit)

          {{DateTime.to_unix(at.(offset)), min(usd, left)},
           Map.put(room, day, left - min(usd, left))}
        end)

      assert Enum.sort(
               Enum.map(spent(account), &{DateTime.to_unix(&1.earned_at), &1.points_micro_delta})
             ) ==
               Enum.sort(expected)
    end
  end

  test "the last second of a day and the first of the next are two days, whenever the site checks them" do
    account = person()
    checked = DateTime.utc_now()
    last = DateTime.add(@midnight, -1)

    assert earned(pay("keyfleet.key_spend", account, last, @limit, qualified_at: checked)) ==
             @limit

    assert earned(
             pay("patchbay.payment_spend", account, @midnight, @limit, qualified_at: checked)
           ) ==
             @limit
  end

  property "a payment reported again, by another rule or account, pays once and writes a 0-point entry" do
    check all(
            reports <-
              list_of({integer(0..2), member_of(@spending), integer(0..1)},
                min_length: 1,
                max_length: 8
              ),
            max_runs: 12
          ) do
      accounts = [person(), person()]
      # Three payments of 10, 20 and 30 dollars: together under the day's limit.
      payments = Enum.map([10_000_000, 20_000_000, 30_000_000], &payment/1)

      for {n, rule, who} <- reports,
          do: pay(rule, Enum.at(accounts, who), @midnight, Enum.at(payments, n))

      paid =
        reports
        |> Enum.uniq_by(&elem(&1, 0))
        |> Enum.map(fn {n, _rule, who} -> {who, Enum.at(payments, n)["usd_micros"]} end)

      for {account, who} <- Enum.with_index(accounts) do
        entries = spent(account)

        assert Enum.sum(Enum.map(entries, & &1.points_micro_delta)) ==
                 Enum.sum(for {^who, usd} <- paid, do: usd)

        assert length(entries) == Enum.count(reports, &(elem(&1, 2) == who))
      end
    end
  end

  test "two payments in one transaction, and one transaction on two chains, each pay" do
    account = person()
    first = %{payment(10_000_000) | "chain_id" => 8453, "log_index" => 3}

    for evidence <- [
          first,
          %{first | "log_index" => 4},
          %{first | "log_index" => 0},
          %{first | "chain_id" => 1}
        ] do
      assert earned(pay("keyfleet.key_spend", account, @midnight, evidence)) == 10_000_000
    end
  end

  # Otherwise a payment the day's limit clipped could earn again for another
  # account, or on another day.
  test "a payment is used by its first report, even when the day's limit clips it to part or to nothing" do
    [a, b] = [person(), person()]
    next_day = DateTime.add(@midnight, 86_400)
    assert earned(pay("keyfleet.key_spend", a, @midnight, 90_000_000)) == 90_000_000

    clipped = payment(50_000_000)
    assert earned(pay("keyfleet.key_spend", a, @midnight, clipped)) == 10_000_000
    full = payment(50_000_000)
    assert earned(pay("keyfleet.key_spend", a, @midnight, full)) == 0

    for evidence <- [clipped, full] do
      assert earned(pay("patchbay.payment_spend", b, @midnight, evidence)) == 0
      assert earned(pay("patchbay.payment_spend", a, next_day, evidence)) == 0
    end
  end

  test "the database lets one payment's row be used only once" do
    row = Store.payment(payment(5_000_000), @midnight)
    RegentPoints.consume_cap!(row, 5_000_000, actor: Store.system())

    assert_raise Ash.Error.Invalid, fn ->
      RegentPoints.consume_cap!(row, 5_000_000, actor: Store.system())
    end
  end

  # A payment awarded to the wrong account can still pay the right one, reported
  # again under the source id the library names, and the wrong account's day
  # stays used. One source id stays one award.
  test "a payment taken back in full is reported again for the right account; a partial take-back frees nothing" do
    [wrong, right] = [person(), person()]
    evidence = payment(60_000_000)
    wrong_key = pay("keyfleet.key_spend", wrong, @midnight, evidence)
    right_key = pay("patchbay.payment_spend", right, @midnight, evidence)
    assert earned(right_key) == 0
    %{id: id} = entry(wrong_key)

    assert {:ok, _} =
             RegentPoints.reverse(id, "part", 20_000_000, "wrong_account", actor: Store.system())

    assert payment_row(evidence) == {1, 60_000_000}
    again = RegentPoints.source_after_take_back(right_key, "part")
    assert earned(pay("patchbay.payment_spend", right, @midnight, evidence, key: again)) == 0

    assert {:ok, _} =
             RegentPoints.reverse(id, "rest", 40_000_000, "wrong_account", actor: Store.system())

    assert payment_row(evidence) == {0, 0}

    report("patchbay.payment_spend", right, @midnight, evidence, key: right_key)
    assert earned(right_key) == 0
    report("keyfleet.key_spend", right, @midnight, evidence, key: wrong_key)
    assert rejections(wrong_key) == ["source_identity_conflict"]

    again = RegentPoints.source_after_take_back(right_key, "rest")

    assert earned(pay("patchbay.payment_spend", right, @midnight, evidence, key: again)) ==
             60_000_000

    assert payment_row(evidence) == {1, 60_000_000}
    assert earned(pay("keyfleet.key_spend", wrong, @midnight, @limit)) == 40_000_000
    assert earned(pay("patchbay.payment_spend", right, @midnight, @limit)) == 40_000_000
  end

  test "a 78-digit token amount on a very large chain id is taken back and reported again exactly" do
    [wrong, right] = [person(), person()]
    amount = String.duplicate("9", 78)
    usd = div(String.to_integer(amount) * 1_000_000, Integer.pow(10, 70))
    huge = Integer.pow(10, 40) + 7

    evidence =
      payment(usd, %{
        "token_amount" => amount,
        "token_decimals" => 70,
        "chain_id" => huge,
        "log_index" => huge * 3
      })

    key = pay("keyfleet.key_spend", wrong, @midnight, evidence)
    assert earned(key) == @limit

    assert {:ok, _} =
             RegentPoints.reverse(entry(key).id, "wrong", @limit, "wrong_account",
               actor: Store.system()
             )

    assert payment_row(evidence) == {0, 0}
    again = RegentPoints.source_after_take_back(key, "wrong")
    assert earned(pay("keyfleet.key_spend", right, @midnight, evidence, key: again)) == @limit
  end

  # A payment that found the wrong account's day full earned 0 but is used, so a
  # 0 correction frees it. Only the award that used the payment can be corrected
  # by 0: not a repeat of it, and not a 0-point action.
  test "a payment that earned 0 for the wrong account is freed by a 0 correction, once" do
    [wrong, right, other] = [person(), person(), person()]
    pay("keyfleet.key_spend", wrong, @midnight, @limit)
    evidence = payment(30_000_000)
    wrong_key = pay("keyfleet.key_spend", wrong, @midnight, evidence)
    %{id: id, points_micro_delta: 0} = entry(wrong_key)
    assert payment_row(evidence) == {1, 0}

    assert {:ok, _} = RegentPoints.reverse(id, "wrong", 0, "wrong_account", actor: Store.system())
    assert payment_row(evidence) == {0, 0}

    assert {:error, error} =
             RegentPoints.reverse(id, "again", 0, "wrong_account", actor: Store.system())

    assert Exception.message(error) =~ "Correction exceeds the original remaining award"
    again = RegentPoints.source_after_take_back(wrong_key, "wrong")
    assert earned(pay("keyfleet.key_spend", right, @midnight, evidence, key: again)) == 30_000_000

    %{id: repeat} = entry(pay("patchbay.payment_spend", other, @midnight, evidence))
    assert {:error, _} = RegentPoints.reverse(repeat, "repeat", 0, "wrong", actor: Store.system())

    for _ <- 1..2, do: report("patchbay.reply_published", other, @midnight, %{})
    assert [_, %{id: action, points_micro_delta: 0}] = entries(other, "activity")
    assert {:error, _} = RegentPoints.reverse(action, "action", 0, "wrong", actor: Store.system())

    assert earned(pay("patchbay.payment_spend", other, @midnight, evidence)) == 0
  end

  test "a positive award is never corrected by 0" do
    account = person()
    evidence = payment(30_000_000)
    paid = entry(pay("keyfleet.key_spend", account, @midnight, evidence))
    {key, {:ok, _}} = report("patchbay.reply_published", account, @midnight, %{})
    action = entry(key)

    for %{id: id} <- [paid, action] do
      assert {:error, _} = RegentPoints.reverse(id, "zero", 0, "wrong", actor: Store.system())
    end

    assert payment_row(evidence) == {1, 30_000_000}
    assert [_] = spent(account)
  end

  # What the database itself refuses, whatever the code above it does. Each
  # refusal ends its test, since a refused statement ends the test's transaction.
  test "the database refuses a 0 correction of an entry that is not a spending award" do
    account = person()
    {key, {:ok, _}} = report("patchbay.reply_published", account, @midnight, %{})
    assert {:error, _} = zero_correction(entry(key), "zero-action")
  end

  test "the database refuses a second 0 correction of one award" do
    account = person()
    pay("keyfleet.key_spend", account, @midnight, @limit)
    zero = entry(pay("keyfleet.key_spend", account, @midnight, payment(5_000_000)))
    assert {:ok, _} = zero_correction(zero, "zero-1")
    assert {:error, _} = zero_correction(zero, "zero-2")
  end

  test "the database keeps one row per payment" do
    row = Store.payment(payment(5_000_000), @midnight)

    fields = %{
      account_id: row.account_id,
      program_id: row.program_id,
      cap_scope: row.cap_scope,
      window_start: row.window_start,
      window_end: row.window_end
    }

    for other <- [
          %{account_id: person()},
          %{program_id: Rules.program()},
          %{window_start: DateTime.to_date(@midnight)}
        ] do
      assert {:error, _} =
               RegentPoints.reserve_cap(Map.merge(fields, other), actor: Store.system())
    end
  end

  property "the holder bonus applies to dollar points like any others" do
    check all(
            percent <- member_of([20, 45, 75]),
            amounts <- list_of(integer(1..80_000_000), min_length: 1, max_length: 4),
            max_runs: 8
          ) do
      account = person()
      bonus = held_bonus(account, percent)
      for usd <- amounts, do: pay("autolaunch.auction_bid_spend", account, @midnight, usd)

      earned = Enum.sum(clip(amounts))

      bonus =
        RegentPoints.read_period_bonuses!(
          query: Ash.Query.filter(RegentPoints.PeriodBonus, id == ^bonus.id),
          actor: Store.system()
        )
        |> hd()

      assert bonus.earned_micro == earned
      assert bonus.bonus_micro == div(earned * percent, 100)

      [balance] =
        RegentPoints.read_accounts!(
          query: Ash.Query.filter(RegentPoints.Account, id == ^account),
          load: [:balance_micro],
          actor: Store.system()
        )

      assert balance.balance_micro == earned + div(earned * percent, 100)
    end
  end

  # The dollars are only what the payment's evidence proves, so a payment the
  # evidence does not name exactly earns nothing.
  test "a payment its evidence does not name exactly earns nothing" do
    account = person()
    good = payment(5_000_000)

    broken =
      Enum.map(Map.keys(good), &Map.delete(good, &1)) ++
        for {key, value} <- [
              {"usd_micros", 0},
              {"usd_micros", 5_000_001},
              {"payer", String.upcase(good["payer"])},
              {"token", String.upcase(good["token"])},
              {"token_amount", 5_000_000},
              {"token_amount", "05000000"},
              {"token_decimals", "6"},
              {"token_decimals", 256},
              {"price_usd", "0.0"},
              {"price_usd", "1e0"},
              {"price_usd", "one"},
              {"price_source", " "},
              {"price_source", String.duplicate("é", 101)},
              {"price_source", "face\0value"},
              {"price_source", <<255, 65>>},
              {"chain_id", "8453"},
              {"chain_id", 0},
              {"block_number", 0},
              {"block_number", "38000000"},
              {"tx_hash", "0x" <> String.upcase(String.slice(good["tx_hash"], 2..-1//1))},
              {"log_index", -1},
              {"log_index", "3"}
            ],
            do: Map.put(good, key, value)

    for evidence <- broken do
      {key, {:ok, _}} = report("patchbay.payment_spend", account, @midnight, evidence)
      assert {earned(key), rejections(key)} == {nil, ["invalid_spending_evidence"]}
    end

    assert spent(account) == []
    assert earned(pay("patchbay.payment_spend", account, @midnight, good)) == 5_000_000

    # A price source of 200 bytes is the longest kept.
    long = payment(5_000_000, %{"price_source" => String.duplicate("é", 100)})
    assert earned(pay("patchbay.payment_spend", account, @midnight, long)) == 5_000_000
  end

  test "a payment's dollars follow from its token amount, decimals and price, rounded down" do
    account = person()

    # 2.5 REGENT at 0.01234567 dollars is 0.030864175 dollars.
    regent = %{
      payment(30_864)
      | "token" => "0x" <> String.duplicate("ab", 20),
        "token_amount" => "2500000000000000000",
        "token_decimals" => 18,
        "price_usd" => "0.01234567",
        "price_source" => "pool"
    }

    {key, {:ok, _}} =
      report("autolaunch.auction_bid_spend", account, @midnight, %{
        regent
        | "usd_micros" => 30_865
      })

    assert rejections(key) == ["invalid_spending_evidence"]
    assert earned(pay("autolaunch.auction_bid_spend", account, @midnight, regent)) == 30_864
  end

  property "the accepted dollars are exactly the floor; one more or one less is refused" do
    check all(
            decimals <- integer(0..36),
            micro_tokens <- integer(1..1_000_000_000_000),
            dust <- integer(0..999),
            whole <- one_of([constant(0), integer(0..9), integer(0..1_000)]),
            fraction <- string(?0..?9, max_length: 12),
            max_runs: 60
          ) do
      amount = max(1, div(micro_tokens * Integer.pow(10, decimals), 1_000_000) + dust)
      price = if fraction == "", do: "#{whole}", else: "#{whole}.#{fraction}"
      floor = if price =~ ~r/[1-9]/, do: floor_usd(amount, price, decimals), else: 0

      evidence =
        payment(floor, %{
          "token_amount" => Integer.to_string(amount),
          "token_decimals" => decimals,
          "price_usd" => price
        })

      cond do
        floor == 0 ->
          for usd <- [0, 1], do: assert(outcome(%{evidence | "usd_micros" => usd}) == refused())

        floor > @ceiling ->
          assert outcome(evidence) == {nil, ["spending_amount_too_large"]}

        true ->
          assert outcome(evidence) == {min(floor, @limit), []}

          assert outcome(%{evidence | "usd_micros" => floor + 1, "tx_hash" => tx()}) in [
                   refused(),
                   {nil, ["spending_amount_too_large"]}
                 ]

          if floor > 1,
            do:
              assert(
                outcome(%{evidence | "usd_micros" => floor - 1, "tx_hash" => tx()}) == refused()
              )
      end
    end
  end

  test "exact boundaries: a fraction of a millionth is dropped, never rounded up" do
    for {amount, decimals, price, usd} <- [
          {"1999999", 6, "1", 1_999_999},
          {"1999999999999999999", 18, "1", 1_999_999},
          {"1", 0, "0.000001", 1},
          {"3", 0, "0.3333339", 1_000_001},
          {"1", 0, "1.9999999", 1_999_999},
          {"999999999999999999", 18, "1.000000000000000001", 999_999},
          {"1000000000000000000", 18, "0.999999999999999999", 999_999},
          {"5", 0, "20", 100_000_000},
          {"1", 6, "1", 1},
          {"25", 1, "0.4", 1_000_000}
        ] do
      evidence =
        payment(usd, %{
          "token_amount" => amount,
          "token_decimals" => decimals,
          "price_usd" => price
        })

      assert outcome(evidence) == {usd, []}
      assert outcome(%{evidence | "usd_micros" => usd + 1, "tx_hash" => tx()}) == refused()
    end

    # Less than a millionth of a dollar proves no dollars at all.
    tiny = payment(1, %{"token_amount" => "1", "token_decimals" => 0, "price_usd" => "0.0000009"})
    assert outcome(tiny) == refused()
  end

  test "token decimals are a whole number from 0 to 255" do
    assert outcome(payment(5_000_000, %{"token_amount" => "5", "token_decimals" => 0})) ==
             {5_000_000, []}

    for decimals <- [-1, 256, 6.0, "6", nil, [6], 1.0e2] do
      assert outcome(payment(5_000_000, %{"token_decimals" => decimals})) == refused()
    end
  end

  test "a token amount is 1 to 78 plain digits with no leading zero" do
    for amount <- [
          "0",
          "",
          "-5000000",
          "+5000000",
          "5000000.0",
          " 5000000",
          "5000000 ",
          "05000000",
          "5e6",
          "5_000_000",
          "0x4c4b40",
          "5000000\n",
          "٥٠٠٠٠٠٠",
          5_000_000,
          5.0e6,
          nil,
          ~c"5000000"
        ] do
      assert outcome(payment(5_000_000, %{"token_amount" => amount})) == refused()
    end

    nines = String.duplicate("9", 78)
    assert outcome(payment(9, %{"token_amount" => nines, "token_decimals" => 84})) == refused()

    widest = payment(999_999, %{"token_amount" => nines, "token_decimals" => 78})
    assert outcome(widest) == {999_999, []}

    too_wide = %{
      widest
      | "token_amount" => nines <> "9",
        "token_decimals" => 79,
        "tx_hash" => tx()
    }

    assert outcome(too_wide) == refused()
  end

  test "a price is plain digits with at most one dot and something above zero" do
    for price <- [
          "1e0",
          "1E0",
          "1e-2",
          "+1",
          "-1",
          " 1",
          "1 ",
          "1.",
          ".5",
          "01",
          "00.5",
          "1,0",
          "1_0",
          "0",
          "0.0",
          "0.000",
          "",
          ".",
          "1.0.0",
          "1..0",
          "0x1",
          "NaN",
          "Infinity",
          "one",
          "١",
          "1\n",
          "1.0\n",
          1,
          1.0,
          nil,
          ["1"],
          ~c"1",
          %{"usd" => "1"}
        ] do
      assert outcome(payment(5_000_000, %{"price_usd" => price})) == refused()
    end

    for price <- ["1.0", "1.000000", "1.00000000000000000000000000"] do
      assert outcome(payment(5_000_000, %{"price_usd" => price})) == {5_000_000, []}
    end
  end

  # A longer price is no real price, and working out its dollars could stop the check.
  test "a price has at most 30 digits each side of the dot" do
    whole = "1" <> String.duplicate("0", 29)
    fraction = "0." <> String.duplicate("0", 29) <> "1"

    assert outcome(
             payment(@ceiling, %{
               "token_amount" => "1",
               "token_decimals" => 20,
               "price_usd" => whole
             })
           ) == {@limit, []}

    assert outcome(
             payment(1_000_000, %{
               "token_amount" => "1" <> String.duplicate("0", 30),
               "token_decimals" => 0,
               "price_usd" => fraction
             })
           ) == {1_000_000, []}

    # Each is a payment whose dollars are right; only the price's length refuses it.
    for {usd, amount, decimals, price} <- [
          {1_000_000, "1", 30, whole <> "0"},
          {1_000_000, "1" <> String.duplicate("0", 31), 0,
           "0." <> String.duplicate("0", 30) <> "1"},
          {5_000_000, "5000000", 6, "1." <> String.duplicate("0", 10_000)},
          {5_000_000, "5000000", 6, "1." <> String.duplicate("0", 2_000_000)}
        ] do
      evidence =
        payment(usd, %{
          "token_amount" => amount,
          "token_decimals" => decimals,
          "price_usd" => price
        })

      assert outcome(evidence) == refused()
    end
  end

  test "every field has one type: a number sent as text, or text sent as a number, is refused" do
    good = payment(5_000_000)

    for {field, value} <- [
          {"usd_micros", "5000000"},
          {"usd_micros", 5.0e6},
          {"usd_micros", 5_000_000.0},
          {"usd_micros", nil},
          {"usd_micros", -5_000_000},
          {"token_decimals", "6"},
          {"token_decimals", 6.0},
          {"chain_id", "8453"},
          {"chain_id", 8453.0},
          {"chain_id", -1},
          {"block_number", "38000000"},
          {"block_number", 38_000_000.0},
          {"block_number", -1},
          {"log_index", "3"},
          {"log_index", 3.0},
          {"token", 0x833589FCD6EDB6E08F4C7C32D4F71B54BDA02913},
          {"token", nil},
          {"tx_hash", 1},
          {"tx_hash", nil},
          {"payer", 1},
          {"price_source", nil},
          {"price_source", 1},
          {"price_source", ""},
          {"price_source", "\n\t "}
        ] do
      assert outcome(Map.put(good, field, value)) == refused()
    end

    assert outcome(good) == {5_000_000, []}
  end

  test "the paying wallet is a lowercase address of exactly 40 hex digits" do
    payer = "0x" <> String.duplicate("ab", 20)

    for bad <- [
          "0x" <> String.duplicate("AB", 20),
          "0X" <> String.duplicate("ab", 20),
          "0x" <> String.duplicate("aB", 20),
          String.duplicate("ab", 20),
          "0x" <> String.duplicate("ab", 19),
          "0x" <> String.duplicate("ab", 19) <> "a",
          "0x" <> String.duplicate("ab", 20) <> "a",
          "0x" <> String.duplicate("ab", 21),
          "0x" <> String.duplicate("zz", 20),
          payer <> "\n",
          " " <> payer,
          "vitalik.eth",
          "",
          nil
        ] do
      assert outcome(payment(5_000_000, %{"payer" => bad})) == refused()
    end

    assert outcome(payment(5_000_000, %{"payer" => payer})) == {5_000_000, []}
  end

  test "a billion dollars is the most a payment can prove; more is refused under its own reason" do
    assert outcome(payment(@ceiling)) == {@limit, []}

    for usd <- [
          @ceiling + 1,
          @ceiling * 10,
          Integer.pow(10, 25),
          Integer.pow(2, 63),
          Integer.pow(10, 80)
        ] do
      evidence =
        payment(usd, %{"token_amount" => Integer.to_string(min(usd, Integer.pow(10, 77)))})

      assert outcome(evidence) == {nil, ["spending_amount_too_large"]}
    end
  end

  # Only the site a rule belongs to proves its payments.
  test "each spending rule is earned only through its own site" do
    for rule <- @spending, app <- ~w(keyfleet patchbay template autolaunch regents techtree) do
      own = rule |> String.split(".") |> hd()
      result = outcome(payment(5_000_000), rule, app: app)

      if app == own,
        do: assert(result == {5_000_000, []}),
        else: assert(result == {nil, ["ineligible_spending_app"]})
    end

    for app <- [
          "Keyfleet",
          "keyfleet ",
          " keyfleet",
          "keyfleet.key_spend",
          "key",
          "k",
          "keyfleet."
        ] do
      assert outcome(payment(5_000_000), "keyfleet.key_spend", app: app) ==
               {nil, ["ineligible_spending_app"]}
    end
  end

  test "a spending rule off the approved list earns nothing" do
    Application.put_env(:regent_points, :approved_rules, @rules -- ["patchbay.payment_spend"])
    account = person()
    {key, result} = report("patchbay.payment_spend", account, @midnight, payment(5_000_000))
    assert {:ok, %{status: :disabled}} = result
    assert earned(key) == nil
  end

  test "the account reads today's dollars out of 100, from today's blocks only" do
    on_one_day(fn today ->
      account = person()
      start = DateTime.new!(today, ~T[00:00:00])
      pay("keyfleet.key_spend", account, DateTime.add(start, -1), 80_000_000)
      pay("keyfleet.key_spend", account, start, 60_000_000)

      assert RegentPoints.summary!(actor: reader(account)).dollars_today ==
               %{counted_micro: 60_000_000, limit_micro: @limit}

      pay("template.pinned_note_spend", account, start, 70_000_000)

      summary = RegentPoints.summary!(actor: reader(account))
      assert summary.dollars_today == %{counted_micro: @limit, limit_micro: @limit}

      assert %{scope: "spending:account", remaining: 0} =
               Enum.find(summary.allowances, &(&1.scope == "spending:account"))
    end)
  end

  # The summary reads today from the clock. A run that crossed midnight UTC is run
  # again, so its "today" is always the day the payments were made on.
  defp on_one_day(check) do
    today = Date.utc_today()

    outcome =
      try do
        check.(today)
      rescue
        error -> {:raised, error, __STACKTRACE__}
      end

    case {Date.utc_today(), outcome} do
      {^today, {:raised, error, stack}} -> reraise error, stack
      {^today, _} -> :ok
      _next_day -> on_one_day(check)
    end
  end

  # Each day's room is 100 dollars; payments fill it in the order they are checked.
  defp clip(amounts) do
    {earned, _room} = Enum.map_reduce(amounts, @limit, &{min(&1, &2), &2 - min(&1, &2)})
    earned
  end

  # A payment of `usd` millionths of a dollar in USDC at face value, from its own
  # wallet, on its own transaction, chain and log.
  defp payment(usd) do
    %{
      "usd_micros" => usd,
      "payer" => "0x" <> hex(20),
      "token" => "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      "token_amount" => Integer.to_string(usd),
      "token_decimals" => 6,
      "price_usd" => "1",
      "price_source" => "face_value",
      "chain_id" => Enum.random([1, 8453, 84_532]),
      "block_number" => 38_000_000,
      "tx_hash" => "0x" <> hex(32),
      "log_index" => Enum.random(0..400)
    }
  end

  defp payment(usd, overrides), do: Map.merge(payment(usd), overrides)

  defp hex(bytes), do: Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)
  defp tx, do: "0x" <> hex(32)

  # What became of one payment reported by a new account: its points and rejections.
  defp outcome(evidence, rule \\ "patchbay.payment_spend", opts \\ []) do
    {key, {:ok, _}} = report(rule, person(), @midnight, evidence, opts)
    {earned(key), rejections(key)}
  end

  defp refused, do: {nil, ["invalid_spending_evidence"]}

  # The dollars a payment proves, in millionths, worked out apart from the library:
  # Decimal reads the price into a whole number and a power of ten.
  defp floor_usd(amount, price, decimals) do
    %Decimal{sign: 1, coef: coef, exp: exp} = Decimal.new(price)
    numerator = amount * coef * 1_000_000

    if exp >= 0,
      do: div(numerator * Integer.pow(10, exp), Integer.pow(10, decimals)),
      else: div(numerator, Integer.pow(10, decimals - exp))
  end

  # One payment's row as {awards, points}, or nil when none was made.
  defp payment_row(%{"chain_id" => chain, "tx_hash" => tx, "log_index" => log}) do
    scope = "payment:" <> Store.digest({chain, tx, log})

    CapUsage
    |> Ash.Query.filter(account_id == 0 and cap_scope == ^scope)
    |> then(&RegentPoints.read_caps!(query: &1, actor: Store.system()))
    |> case do
      [cap] -> {cap.award_count, cap.points_micro}
      [] -> nil
    end
  end

  # A 0 correction written straight through the ledger's own append.
  defp zero_correction(original, key) do
    original
    |> Map.take([
      :program_id,
      :account_id,
      :event_id,
      :rule_id,
      :rule_version,
      :source_app,
      :actor_kind,
      :actor_id,
      :category,
      :milestone_key,
      :earned_at
    ])
    |> Map.merge(%{
      award_key: key,
      points_micro_delta: 0,
      reversal_of_entry_id: original.id,
      reason_code: "test"
    })
    |> RegentPoints.append_entry(actor: Store.system())
  end

  defp pay(rule, account, at, usd_or_evidence, opts \\ [])

  defp pay(rule, account, at, usd, opts) when is_integer(usd),
    do: pay(rule, account, at, payment(usd), opts)

  defp pay(rule, account, at, evidence, opts) do
    {key, {:ok, _}} = report(rule, account, at, evidence, opts)
    key
  end

  # Saves the source's facts and records the action the way a site does: at the
  # block's time, checked then or at `qualified_at`, by the rule's own site or `app`,
  # under its own source id or `key`.
  defp report(rule, account, at, evidence, opts \\ []) do
    app = Keyword.get(opts, :app, rule |> String.split(".") |> hd())
    key = Keyword.get_lazy(opts, :key, fn -> "report-" <> hex(16) end)

    facts = %{
      source_app: app,
      source_kind: "test",
      source_event_key: key,
      account_id: account,
      actor_kind: "human",
      actor_id: to_string(account),
      source_action_at: at,
      qualified_at: Keyword.get(opts, :qualified_at, at),
      evidence_ref: "test:" <> key,
      evidence: Map.merge(evidence, key_proof(rule, key))
    }

    saved = Application.get_env(:regent_points, :test_facts, %{})
    Application.put_env(:regent_points, :test_facts, Map.put(saved, key, facts))

    {key,
     RegentPoints.record_event(
       %{rule_id: rule, source_app: app, source_kind: "test", source_event_key: key},
       actor: Store.system()
     )}
  end

  # Keyfleet's awards also name the Key and its owner's epoch, as every Keyfleet rule does.
  defp key_proof("keyfleet." <> _, key), do: %{"key_id" => key, "ownership_epoch" => "1"}
  defp key_proof(_rule, _key), do: %{}

  # The award one report wrote, or nil when it wrote none.
  defp entry(key) do
    Event
    |> Ash.Query.filter(source_event_key == ^key)
    |> then(&RegentPoints.read_events!(query: &1, actor: Store.system()))
    |> Enum.flat_map(fn event ->
      Entry
      |> Ash.Query.filter(event_id == ^event.id and is_nil(reversal_of_entry_id))
      |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
    end)
    |> List.first()
  end

  defp earned(key), do: with(%{points_micro_delta: points} <- entry(key), do: points)

  defp rejections(key) do
    for rejection <- RegentPoints.read_rejections!(actor: Store.system()),
        rejection.source["source_event_key"] == key,
        do: rejection.reason_code
  end

  # The period-end tier the tally saved for the account's first period.
  defp held_bonus(account, percent) do
    {starts, ends} = Rules.period(1)

    snapshot =
      Ash.create!(
        RegentPoints.PeriodSnapshot,
        %{
          program_id: "spending-test-#{account}",
          period: 1,
          starts_at: starts,
          ends_at: ends,
          block_number: 1,
          block_hash: "0x01",
          block_at: ends
        },
        action: :record,
        actor: Store.system()
      )

    RegentPoints.open_account!(%{id: account}, actor: Store.system())

    RegentPoints.record_period_bonus!(
      %{
        program_id: Rules.program(),
        account_id: account,
        period: 1,
        snapshot_id: snapshot.id,
        earned_micro: 0,
        nft_count: 1,
        nft_block: 1,
        bonus_percent: percent,
        bonus_micro: 0
      },
      actor: Store.system()
    )
  end

  defp reader(account), do: %{role: :human, human_account_id: account}

  defp person do
    %{rows: [[id]]} =
      RegentPoints.Repo.query!(
        "INSERT INTO regent_names.platform_human_users DEFAULT VALUES RETURNING id"
      )

    id
  end

  defp spent(account), do: entries(account, "spending")

  defp entries(account, category) do
    Entry
    |> Ash.Query.filter(
      account_id == ^account and program_id == ^Rules.program() and category == ^category
    )
    |> Ash.Query.sort(recorded_at: :asc)
    |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
  end
end

defmodule RegentPoints.SpendingTest do
  # Dollar points: one point per dollar a payment proves, at most 100 dollars an
  # account a UTC day, each payment paid once. Payments are recorded the way a site
  # records them, on a real database, with Oban running each job as it is queued.
  use ExUnit.Case, async: false
  use ExUnitProperties
  require Ash.Query
  alias RegentPoints.{Entry, Event, Rules, Store}

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

  # A payment awarded to the wrong account can still pay the right one, but the
  # wrong account's day stays used.
  test "a payment taken back in full can pay the right account; a partial take-back frees nothing" do
    [wrong, right] = [person(), person()]
    evidence = payment(60_000_000)
    %{id: id} = entry(pay("keyfleet.key_spend", wrong, @midnight, evidence))

    assert {:ok, _} =
             RegentPoints.reverse(id, "part", 20_000_000, "wrong_account", actor: Store.system())

    assert earned(pay("keyfleet.key_spend", right, @midnight, evidence)) == 0

    assert {:ok, _} =
             RegentPoints.reverse(id, "rest", 40_000_000, "wrong_account", actor: Store.system())

    assert earned(pay("keyfleet.key_spend", right, @midnight, evidence)) == 60_000_000
    assert earned(pay("keyfleet.key_spend", wrong, @midnight, @limit)) == 40_000_000
  end

  # A payment that found the wrong account's day full earned 0 but is used, so a
  # 0 correction frees it. Only the award that used the payment can be corrected
  # by 0: not a repeat of it, and not a 0-point action.
  test "a payment that earned 0 for the wrong account is freed by a 0 correction" do
    [wrong, right, other] = [person(), person(), person()]
    pay("keyfleet.key_spend", wrong, @midnight, @limit)
    evidence = payment(30_000_000)

    %{id: id, points_micro_delta: 0} =
      entry(pay("keyfleet.key_spend", wrong, @midnight, evidence))

    assert {:ok, _} = RegentPoints.reverse(id, "wrong", 0, "wrong_account", actor: Store.system())

    assert {:error, _} =
             RegentPoints.reverse(id, "again", 0, "wrong_account", actor: Store.system())

    assert earned(pay("keyfleet.key_spend", right, @midnight, evidence)) == 30_000_000

    %{id: repeat} = entry(pay("patchbay.payment_spend", other, @midnight, evidence))
    assert {:error, _} = RegentPoints.reverse(repeat, "repeat", 0, "wrong", actor: Store.system())

    for _ <- 1..2, do: report("patchbay.reply_published", other, @midnight, %{})
    assert [_, %{id: action, points_micro_delta: 0}] = entries(other, "activity")
    assert {:error, _} = RegentPoints.reverse(action, "action", 0, "wrong", actor: Store.system())

    assert earned(pay("patchbay.payment_spend", other, @midnight, evidence)) == 0
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

  test "a payment of more than a billion dollars is refused" do
    account = person()
    billion = 1_000_000_000_000_000
    assert earned(pay("patchbay.payment_spend", account, @midnight, billion)) == @limit
    {key, {:ok, _}} = report("patchbay.payment_spend", account, @midnight, payment(billion + 1))
    assert rejections(key) == ["spending_amount_too_large"]
  end

  # Only the site a rule belongs to proves its payments: Keyfleet cannot report an
  # Autolaunch bid, nor another site the template's pinned note.
  test "a spending rule reported by another site earns nothing" do
    account = person()

    for {rule, app} <- [
          {"autolaunch.auction_bid_spend", "keyfleet"},
          {"template.pinned_note_spend", "patchbay"}
        ] do
      {key, {:ok, _}} = report(rule, account, @midnight, payment(5_000_000), app: app)
      assert rejections(key) == ["ineligible_spending_app"]
    end

    assert spent(account) == []
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

  defp hex(bytes), do: Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)

  defp pay(rule, account, at, usd_or_evidence, opts \\ [])

  defp pay(rule, account, at, usd, opts) when is_integer(usd),
    do: pay(rule, account, at, payment(usd), opts)

  defp pay(rule, account, at, evidence, opts) do
    {key, {:ok, _}} = report(rule, account, at, evidence, opts)
    key
  end

  # Saves the source's facts and records the action the way a site does: at the
  # block's time, checked then or at `qualified_at`, by the rule's own site or `app`.
  defp report(rule, account, at, evidence, opts \\ []) do
    app = Keyword.get(opts, :app, rule |> String.split(".") |> hd())
    key = "report-" <> hex(16)

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

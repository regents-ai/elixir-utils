defmodule RegentPoints.SpendingTest do
  # Dollar points: one point per dollar a payment proves, at most 100 dollars an
  # account a UTC day. Payments are recorded the way a site records them, on a real
  # database, with Oban running each job as it is queued.
  use ExUnit.Case, async: false
  use ExUnitProperties
  require Ash.Query
  alias RegentPoints.{Entry, Rules, Store}

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

  @spending ~w(keyfleet.key_spend patchbay.payment_spend template.pinned_note_spend autolaunch.auction_bid_spend autolaunch.token_buy_spend)
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
      earn_reply(account, @midnight)

      for {rule, usd} <- payments, do: pay(rule, account, @midnight, usd)

      expected = clip(Enum.map(payments, &elem(&1, 1)))
      assert Enum.map(spent(account), & &1.points_micro_delta) == expected
      assert Enum.sum(expected) == min(@limit, Enum.sum(Enum.map(payments, &elem(&1, 1))))
    end
  end

  property "a payment counts on the UTC day of its block" do
    check all(
            payments <-
              list_of({integer(-7_200..7_199), integer(1..150_000_000)},
                min_length: 1,
                max_length: 6
              ),
            max_runs: 12
          ) do
      account = person()
      at = fn offset -> DateTime.add(@midnight, offset) end
      for {offset, usd} <- payments, do: pay("keyfleet.key_spend", account, at.(offset), usd)

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

  property "a payment reported again, by another rule, site or account, pays once" do
    check all(
            reports <-
              list_of({integer(0..2), member_of(@spending), integer(0..1)},
                min_length: 1,
                max_length: 8
              ),
            max_runs: 12
          ) do
      accounts = {person(), person()}
      # Three payments of 10, 20 and 30 dollars: together under the day's limit.
      payments =
        for usd <- [10_000_000, 20_000_000, 30_000_000],
            do: {Map.put(elem(payment(), 0), "usd_micros", usd), usd}

      reports
      |> Enum.with_index()
      |> Enum.each(fn {{n, rule, who}, i} ->
        {evidence, _usd} = Enum.at(payments, n)
        pay(rule, elem(accounts, who), @midnight, evidence, "report-#{elem(accounts, 0)}-#{i}")
      end)

      paid =
        reports
        |> Enum.uniq_by(&elem(&1, 0))
        |> Enum.map(fn {n, _rule, who} ->
          {elem(accounts, who), elem(Enum.at(payments, n), 1)}
        end)

      for account <- Tuple.to_list(accounts) do
        assert Enum.sum(Enum.map(spent(account), & &1.points_micro_delta)) ==
                 Enum.sum(for {^account, usd} <- paid, do: usd)
      end
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
      for usd <- amounts, do: pay("autolaunch.token_buy_spend", account, @midnight, usd)

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
  test "a payment without its token, amount, price, chain, block, transaction or log earns nothing" do
    account = person()
    {good, _} = payment()

    for {broken, i} <-
          Enum.with_index([
            Map.delete(good, "price_source"),
            Map.put(good, "tx_hash", String.upcase(good["tx_hash"])),
            Map.put(good, "usd_micros", 0),
            Map.put(good, "price_usd", "0.0"),
            Map.put(good, "token_amount", 5)
          ]) do
      pay("patchbay.payment_spend", account, @midnight, broken, "broken-#{i}")
    end

    assert spent(account) == []

    assert RegentPoints.read_rejections!(actor: Store.system())
           |> Enum.filter(&(&1.source["source_event_key"] =~ ~r/^broken-/))
           |> Enum.map(& &1.reason_code)
           |> Enum.uniq() == ["invalid_spending_evidence"]
  end

  test "the account reads today's dollars out of 100" do
    account = person()
    now = DateTime.utc_now()
    pay("keyfleet.key_spend", account, now, 60_000_000)

    assert %{counted_micro: 60_000_000, limit_micro: @limit} =
             RegentPoints.summary!(actor: reader(account)).dollars_today

    pay("template.pinned_note_spend", account, now, 70_000_000)

    summary = RegentPoints.summary!(actor: reader(account))
    assert summary.dollars_today == %{counted_micro: @limit, limit_micro: @limit}

    assert %{scope: "spending:account", remaining: 0} =
             Enum.find(summary.allowances, &(&1.scope == "spending:account"))
  end

  # Each day's room is 100 dollars; payments fill it in the order they are checked.
  defp clip(amounts) do
    {earned, _room} = Enum.map_reduce(amounts, @limit, &{min(&1, &2), &2 - min(&1, &2)})
    earned
  end

  defp payment do
    usd = 1_000_000

    {%{
       "usd_micros" => usd,
       "token" => "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
       "token_amount" => "1000000",
       "price_usd" => "1",
       "price_source" => "face_value",
       "chain_id" => 8453,
       "block_number" => 38_000_000,
       "tx_hash" => "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
       "log_index" => 3
     }, usd}
  end

  defp pay(rule, account, at, usd) when is_integer(usd) do
    {evidence, _} = payment()
    pay(rule, account, at, Map.put(evidence, "usd_micros", usd), evidence["tx_hash"])
  end

  defp pay(rule, account, at, %{} = evidence, key) do
    app = rule |> String.split(".") |> hd()
    earn(rule, account, at, Map.merge(evidence, key_proof(app, key)), app, key)
  end

  # Keyfleet's awards also name the Key and its owner's epoch, as every Keyfleet rule does.
  defp key_proof("keyfleet", key), do: %{"key_id" => key, "ownership_epoch" => "1"}
  defp key_proof(_app, _key), do: %{}

  defp earn_reply(account, at),
    do: earn("patchbay.reply_published", account, at, %{}, "patchbay", "reply:#{account}")

  # Saves the source's facts and records the action the way a site does.
  defp earn(rule_id, account, at, evidence, app, key) do
    facts = %{
      source_app: app,
      source_kind: "test",
      source_event_key: key,
      account_id: account,
      actor_kind: "human",
      actor_id: to_string(account),
      source_action_at: at,
      qualified_at: at,
      evidence_ref: "test:" <> key,
      evidence: evidence
    }

    saved = Application.get_env(:regent_points, :test_facts, %{})
    Application.put_env(:regent_points, :test_facts, Map.put(saved, key, facts))

    assert {:ok, _} =
             RegentPoints.record_event(
               %{rule_id: rule_id, source_app: app, source_kind: "test", source_event_key: key},
               actor: Store.system()
             )
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

  defp spent(account) do
    Entry
    |> Ash.Query.filter(
      account_id == ^account and program_id == ^Rules.program() and category == "spending"
    )
    |> Ash.Query.sort(recorded_at: :asc)
    |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
  end
end

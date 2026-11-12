defmodule RegentPoints.PageReadsTest do
  # What the Points page reads: one person's figures by day and what they have done
  # of each action, and the board a site reads once for every reader. Actions are
  # recorded the way a site records them, on a real database, with Oban running each
  # job as it is queued.
  use ExUnit.Case, async: false
  use ExUnitProperties
  require Ash.Query
  alias RegentPoints.Store

  defmodule Source do
    @moduledoc false
    def verify(%{"source_event_key" => key}),
      do: Map.fetch(Application.get_env(:regent_points, :test_facts, %{}), key)
  end

  defmodule People do
    @moduledoc false
    # A site's account lookups: a public name and pictures, and nothing else.
    @behaviour RegentPoints.Accounts

    @impl true
    def human(_id), do: %{wallet_address: nil, wallet_addresses: []}

    @impl true
    def agent_names(_id, _ids), do: {:ok, %{}}

    @impl true
    def people(ids),
      do:
        {:ok,
         Map.new(
           ids,
           &{&1,
            %{
              name: "Person #{&1}",
              wallet: "0x#{&1}",
              ens_name: nil,
              squares: nil,
              picture: nil,
              email: "kept@example.com"
            }}
         )}
  end

  @rules ~w(account.activated social.x social.github social.farcaster)
  @start DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -5 * 86_400)

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

    Application.put_env(:regent_points, :program_id, "page-reads-test")
    Application.put_env(:regent_points, :starts_at, @start)
    Application.put_env(:regent_points, :approved_rules, @rules)
    Application.put_env(:regent_points, :adapters, Map.new(@rules, &{&1, Source}))
    Application.put_env(:regent_points, :accounts, People)
    :ok
  end

  test "today and yesterday each count only their own UTC day" do
    account = person()
    now = DateTime.utc_now()
    earn("account.activated", account, DateTime.add(now, -3 * 86_400))
    earn("social.x", account, DateTime.add(now, -86_400))

    summary = RegentPoints.summary!(actor: reader(account))

    assert summary.balance_micro == 35_000_000
    assert summary.earned_yesterday_micro == 10_000_000
    assert summary.earned_today_micro == 0
  end

  test "an action done once is counted done, and one not done is not" do
    account = person()
    earn("account.activated", account, DateTime.utc_now())

    assert %{"account.activated" => 1, "social.x" => 0} =
             RegentPoints.summary!(actor: reader(account)).done
  end

  test "the board orders by total, shares a place on a tie and leaves out zero" do
    [first, level_a, level_b, last, none] = for _ <- 1..5, do: person()
    now = DateTime.utc_now()

    for account <- [first, level_a, level_b], do: earn("account.activated", account, now)
    earn("social.x", first, now)
    earn("social.x", last, now)
    RegentPoints.open_account!(%{id: none}, actor: Store.system())

    assert %{top: top} = RegentPoints.leaderboard!(actor: Store.system())

    assert Enum.map(top, &{&1.rank, &1.points_micro}) == [
             {1, 35_000_000},
             {2, 25_000_000},
             {2, 25_000_000},
             {4, 10_000_000}
           ]

    # Inside a tie the lower account id comes first, so every read agrees.
    assert Enum.map(top, & &1.account_id) ==
             [first, min(level_a, level_b), max(level_a, level_b), last]

    assert RegentPoints.summary!(actor: reader(level_b)).place == 2
    assert RegentPoints.summary!(actor: reader(last)).place == 4
    assert RegentPoints.summary!(actor: reader(none)).place == nil
  end

  test "the board lists ten rows, and a reader below them has their place in their summary" do
    now = DateTime.utc_now()
    for _ <- 1..10, do: earn("account.activated", person(), now)
    below = person()
    earn("social.x", below, now)

    assert %{top: top} = RegentPoints.leaderboard!(actor: Store.system())
    assert length(top) == 10
    refute Enum.any?(top, &(&1.account_id == below))
    assert RegentPoints.summary!(actor: reader(below)).place == 11
  end

  # The board carries account ids for the site to keep, so only the site reads it.
  test "a person cannot read the board themselves" do
    account = person()
    earn("account.activated", account, DateTime.utc_now())

    assert {:error, %Ash.Error.Forbidden{}} = RegentPoints.leaderboard(actor: reader(account))
  end

  # A row carries the name, wallet and pictures the site supplied, its place and its
  # total, and the account id the site needs to mark the reader's own row: nothing
  # else the site's lookup happened to return.
  test "a row holds a name, a wallet, pictures, a place, a total and the account id" do
    earn("account.activated", person(), DateTime.utc_now())

    assert %{top: [row]} = RegentPoints.leaderboard!(actor: Store.system())

    assert row |> Map.keys() |> Enum.sort() ==
             [:account_id, :ens_name, :name, :picture, :points_micro, :rank, :squares, :wallet]
  end

  # An award, a period bonus, a later award the bonus follows and a correction each
  # move the stored total with the ledger, and the board shows each step.
  test "every ledger write moves the account's total, and the board follows" do
    [account, other] = for _ <- 1..2, do: person()
    now = DateTime.utc_now()
    earn("account.activated", account, now)
    earn("social.x", account, now)
    earn("account.activated", other, now)
    assert board_points() == [{account, 35_000_000}, {other, 25_000_000}]

    # The period's tally at 20%, written the way RegentPoints.TallyAccount writes it.
    bonus(account, 20)
    assert board_points() == [{account, 42_000_000}, {other, 25_000_000}]

    # A later award in the tallied period: its bonus follows to 20% of 45.
    earn("social.github", account, now)
    assert board_points() == [{account, 54_000_000}, {other, 25_000_000}]

    # A correction of 4 of the 10 X points: 41 earned, and the bonus follows to 8.2.
    x = Enum.find(entries(account), &(&1.rule_id == "social.x"))
    RegentPoints.reverse!(x.id, "wrong-account", 4_000_000, "test", actor: Store.system())
    assert board_points() == [{account, 49_200_000}, {other, 25_000_000}]

    assert RegentPoints.summary!(actor: reader(account)).balance_micro == 49_200_000
    for id <- [account, other], do: assert(stored(id) == ledger(id))
  end

  # The board reads ten rows from the index on stored totals, and a reader's place is
  # one count on that index; neither touches the ledger or sorts every account.
  test "the board and a place are bounded reads of the stored totals" do
    for _ <- 1..3, do: earn("account.activated", person(), DateTime.utc_now())
    reader = person()
    earn("social.x", reader, DateTime.utc_now())

    board = queries(fn -> RegentPoints.leaderboard!(actor: Store.system()) end)
    assert [{sql, params}] = Enum.filter(board, fn {sql, _} -> sql =~ ~s("accounts") end)
    assert sql =~ ~r/LIMIT \$\d+/ and 10 in params
    assert_bounded(sql, params)

    summary = queries(fn -> RegentPoints.summary!(actor: reader(reader)) end)

    assert [{sql, params}] =
             Enum.filter(summary, fn {sql, _} -> sql =~ ~s("accounts") and sql =~ ~r/count\(/i end)

    assert_bounded(sql, params)
  end

  # Each account earns some of four one-time awards (25, 10, 10 and 10), so many are
  # level on points, and some get a period bonus or a correction; the accounts from
  # earlier runs stay, so the field grows.
  property "stored totals equal the ledger, and the board and places follow from them" do
    # Each number's bits pick which of the four awards one account earns, a bonus
    # and a correction.
    check all(earned <- list_of(integer(0..63), min_length: 1, max_length: 6), max_runs: 12) do
      now = DateTime.utc_now()

      for bits <- earned do
        account = person()

        for {rule, bit} <- Enum.with_index(@rules),
            Bitwise.band(bits, Bitwise.bsl(1, bit)) != 0,
            do: earn(rule, account, now)

        if Bitwise.band(bits, 16) != 0 and entries(account) != [], do: bonus(account, 45)

        if Bitwise.band(bits, 32) != 0 and entries(account) != [] do
          [first | _] = entries(account)
          RegentPoints.reverse!(first.id, "k", 1_000_000, "test", actor: Store.system())
        end
      end

      ledger =
        RegentPoints.read_accounts!(actor: Store.system())
        |> Enum.map(&{&1.id, ledger(&1.id)})

      for {id, total} <- ledger, do: assert(stored(id) == total)

      ranked =
        ledger |> Enum.filter(&(elem(&1, 1) > 0)) |> Enum.sort_by(&{-elem(&1, 1), elem(&1, 0)})

      place = fn total -> if total > 0, do: Enum.count(ledger, &(elem(&1, 1) > total)) + 1 end

      %{top: top} = RegentPoints.leaderboard!(actor: Store.system())
      assert Enum.map(top, &{&1.account_id, &1.points_micro}) == Enum.take(ranked, 10)
      for row <- top, do: assert(row.rank == place.(row.points_micro))

      for {id, total} <- ledger do
        assert RegentPoints.summary!(actor: reader(id)).place == place.(total)
      end
    end
  end

  defp board_points do
    RegentPoints.leaderboard!(actor: Store.system()).top
    |> Enum.map(&{&1.account_id, &1.points_micro})
  end

  defp entries(account) do
    RegentPoints.Entry
    |> Ash.Query.filter(account_id == ^account and is_nil(reversal_of_entry_id))
    |> Ash.Query.sort(recorded_at: :asc, id: :asc)
    |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
  end

  defp stored(account) do
    [%{balance_micro: total}] =
      RegentPoints.read_accounts!(
        query: Ash.Query.filter(RegentPoints.Account, id == ^account),
        actor: Store.system()
      )

    total
  end

  # The account's total summed from its ledger rows, the way the board read it before
  # totals were stored.
  defp ledger(account) do
    %{rows: [[total]]} =
      RegentPoints.Repo.query!(
        """
        SELECT coalesce((SELECT sum(points_micro_delta) FROM regent_points.point_entries WHERE account_id = $1), 0)
             + coalesce((SELECT sum(bonus_micro) FROM regent_points.period_bonuses WHERE account_id = $1), 0)
        """,
        [account]
      )

    Decimal.to_integer(total)
  end

  # Records the account's bonus for the current period at `percent`, under its lock,
  # the way RegentPoints.TallyAccount does once the period's snapshot is read.
  defp bonus(account, percent) do
    program = RegentPoints.Rules.program()
    period = RegentPoints.Rules.period_of(DateTime.utc_now())
    {starts_at, ends_at} = RegentPoints.Rules.period(period)

    snapshot =
      Ash.Seed.seed!(RegentPoints.PeriodSnapshot, %{
        program_id: "#{program}:#{account}",
        period: period,
        starts_at: starts_at,
        ends_at: ends_at,
        block_number: 1,
        block_hash: "0x01",
        block_at: ends_at
      })

    {:ok, _} =
      Ash.transact(RegentPoints.Account, fn ->
        Store.lock_account(account)
        earned = Store.period_earned(account, program, period)

        RegentPoints.record_period_bonus!(
          %{
            program_id: program,
            account_id: account,
            period: period,
            snapshot_id: snapshot.id,
            earned_micro: earned,
            nft_count: 1,
            nft_block: 1,
            bonus_percent: percent,
            bonus_micro: div(earned * percent, 100)
          },
          actor: Store.system()
        )
      end)
  end

  # The SQL and parameters `fun` sends.
  defp queries(fun) do
    test = self()
    handler = "queries-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      [:regent_points, :repo, :query],
      fn _event, _measures, meta, _ -> send(test, {:query, meta.query, meta.params}) end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect([])
  end

  defp collect(sent) do
    receive do
      {:query, sql, params} -> collect([{sql, params} | sent])
    after
      0 -> Enum.reverse(sent)
    end
  end

  # The query reads only the accounts table, through the board's index, and never
  # sorts the rows it finds: its cost is the rows it returns or counts, not the
  # ledger or every account. Sequential scans are off for this one plan so the
  # index is chosen however few rows the test holds.
  defp assert_bounded(sql, params) do
    refute sql =~ "point_entries"
    refute sql =~ "period_bonuses"

    RegentPoints.Repo.query!("SET LOCAL enable_seqscan = off")
    %{rows: rows} = RegentPoints.Repo.query!("EXPLAIN " <> sql, params)
    plan = Enum.map_join(rows, "\n", &hd/1)

    assert plan =~ "accounts_balance_micro_id_index"
    refute plan =~ "Sort"
  end

  defp reader(account), do: %{role: :human, human_account_id: account}

  defp person do
    %{rows: [[id]]} =
      RegentPoints.Repo.query!(
        "INSERT INTO regent_names.platform_human_users DEFAULT VALUES RETURNING id"
      )

    id
  end

  # A linked social account is proven by the account it names.
  defp evidence("social." <> _, key), do: %{"subject_key" => key}
  defp evidence(_rule_id, _key), do: %{}

  # Saves the source's facts and records the action the way a site does.
  defp earn(rule_id, account, at) do
    key = "#{rule_id}:#{account}"

    facts = %{
      source_app: "site-a",
      source_kind: "test",
      source_event_key: key,
      account_id: account,
      actor_kind: "human",
      actor_id: to_string(account),
      source_action_at: at,
      qualified_at: at,
      evidence_ref: "test:" <> key,
      evidence: evidence(rule_id, key)
    }

    saved = Application.get_env(:regent_points, :test_facts, %{})
    Application.put_env(:regent_points, :test_facts, Map.put(saved, key, facts))

    assert {:ok, _} =
             RegentPoints.record_event(
               %{
                 rule_id: rule_id,
                 source_app: "site-a",
                 source_kind: "test",
                 source_event_key: key
               },
               actor: Store.system()
             )
  end
end

defmodule RegentPoints.SeasonsTest do
  # Points runs in three 30-day seasons from the start, and stops by itself after
  # the last one's end: nothing done after it earns, while what was earned inside a
  # season keeps counting, can still be corrected, and still gets its season's
  # bonus. Actions are recorded the way a site records them, on a real database.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: RegentPoints.Repo
  require Ash.Query

  alias RegentPoints.{
    Entry,
    PeriodBonus,
    Rules,
    Seasons,
    StartAwards,
    Store,
    TallyAccount,
    TallyPeriods
  }

  defmodule Source do
    @moduledoc false
    def verify(%{"source_event_key" => key}),
      do: Map.fetch(Application.get_env(:regent_points, :test_facts, %{}), key)

    def existing(rule_id, _start) do
      for {account, %{rule_id: ^rule_id} = reference} <-
            Application.get_env(:regent_points, :test_existing, []),
          do: {account, Map.delete(reference, :rule_id)}
    end
  end

  defmodule People do
    @moduledoc false
    # A site's account lookups; the summary asks only for agents' names.
    @behaviour RegentPoints.Accounts

    @impl true
    def human(_id), do: %{wallet_address: nil, wallet_addresses: []}

    @impl true
    def agent_names(_id, _ids), do: {:ok, %{}}

    @impl true
    def people(_ids), do: {:ok, %{}}
  end

  # Base for the last season's tally: blocks two seconds apart around its end, and
  # one piece of each collection in every wallet.
  defmodule Chain do
    @moduledoc false
    def rpc(_chain, "eth_getBlockByNumber", [tag, false]) do
      number =
        if tag == "finalized",
          do: 101,
          else: String.to_integer(String.trim_leading(tag, "0x"), 16)

      stop = Application.fetch_env!(:regent_points, :test_stop)
      timestamp = if number == 0, do: 0, else: DateTime.to_unix(stop) - 200 + 2 * number

      {:ok,
       %{
         "number" => hex(number),
         "hash" => hash(number),
         "parentHash" => hash(max(number - 1, 0)),
         "timestamp" => hex(timestamp)
       }}
    end

    def rpc(_chain, "eth_call", [_call, %{requireCanonical: true}]),
      do: {:ok, "0x" <> String.pad_leading("1", 64, "0")}

    defp hex(n), do: "0x" <> Integer.to_string(n, 16)
    defp hash(n), do: "0x" <> String.pad_leading(Integer.to_string(n, 16), 64, "0")
  end

  @rules ~w(account.activated patchbay.reply_published)
  @day 86_400

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentPoints.Repo)

    keys =
      ~w(program_id starts_at approved_rules adapters accounts test_facts test_existing chain_client test_stop)a

    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    Application.put_env(:regent_points, :program_id, "seasons-test")
    Application.put_env(:regent_points, :approved_rules, @rules)
    Application.put_env(:regent_points, :adapters, Map.new(@rules, &{&1, Source}))
    Application.put_env(:regent_points, :accounts, People)
    :ok
  end

  test "from a given start, each season follows the last for 30 days, one running at a time" do
    Application.put_env(:regent_points, :starts_at, nil)

    assert Enum.map(Seasons.at(~U[2027-03-01 00:00:00Z]), &{&1.state, &1.starts_at}) ==
             List.duplicate({:upcoming, nil}, 3)

    start = ~U[2027-01-10 12:00:00Z]
    Application.put_env(:regent_points, :starts_at, start)

    assert [
             %{season: 1, starts_at: ^start, ends_at: ~U[2027-02-09 12:00:00Z]},
             %{season: 2, starts_at: ~U[2027-02-09 12:00:00Z], ends_at: ~U[2027-03-11 12:00:00Z]},
             %{season: 3, starts_at: ~U[2027-03-11 12:00:00Z], ends_at: ~U[2027-04-10 12:00:00Z]}
           ] = Seasons.at(start)

    assert Rules.ends_at() == ~U[2027-04-10 12:00:00Z]
    assert states(DateTime.add(start, -1)) == {:before, [:upcoming, :upcoming, :upcoming], nil}
    assert states(start) == {:running, [:running, :upcoming, :upcoming], 30}
    # Part of a day left counts as a day.
    assert states(~U[2027-02-09 11:00:00Z]) == {:running, [:running, :upcoming, :upcoming], 1}
    assert states(~U[2027-02-09 12:00:00Z]) == {:running, [:ended, :running, :upcoming], 30}
    assert states(~U[2027-03-20 12:00:00Z]) == {:running, [:ended, :ended, :running], 21}
    assert states(~U[2027-04-10 12:00:00Z]) == {:ended, [:ended, :ended, :ended], nil}
  end

  test "an action just before the last season's end earns, and one just after earns nothing" do
    stop = ended()
    [inside, outside] = [person(), person()]

    earn("patchbay.reply_published", inside, DateTime.add(stop, -1))
    earn("patchbay.reply_published", outside, stop)

    assert [%{points_micro_delta: 5_000_000}] = entries(inside)
    assert entries(outside) == []
    # Refused the way an action before the start is.
    assert rejected(outside) == ["rule_not_active"]
  end

  test "the start awards are not given after the end" do
    stop = ended()
    account = person()

    Application.put_env(:regent_points, :test_existing, [
      {account, reference("account.activated", "account:#{account}")}
    ])

    put_facts("account:#{account}", account, DateTime.add(stop, -100 * @day))

    assert {:cancel, :ended} = StartAwards.perform(%Oban.Job{})
    assert entries(account) == []
  end

  test "after the end an award from the last season can still be corrected, and reads follow" do
    stop = ended()
    account = person()
    earn("patchbay.reply_published", account, DateTime.add(stop, -@day))
    [award] = entries(account)

    assert {:ok, _} =
             RegentPoints.reverse(award.id, "late-check", 2_000_000, "source_removed",
               actor: Store.system()
             )

    assert Enum.map(entries(account), & &1.points_micro_delta) == [5_000_000, -2_000_000]

    assert %{balance_micro: 3_000_000, current_period: nil, allowances: []} =
             RegentPoints.summary!(actor: %{role: :human, human_account_id: account})
  end

  test "long after the end, the daily tally queues the last season's bonus and none after it" do
    start = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -200 * @day)
    Application.put_env(:regent_points, :starts_at, start)
    account = person()
    earn("patchbay.reply_published", account, DateTime.add(start, 70 * @day))
    earn("patchbay.reply_published", account, DateTime.add(start, 100 * @day))
    assert [%{points_micro_delta: 5_000_000}] = entries(account)

    event = [:regent_points, :tally_periods, :finished]
    ref = :telemetry_test.attach_event_handlers(self(), [event])

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = TallyPeriods.perform(%Oban.Job{})
      assert_enqueued(worker: TallyAccount, args: %{account_id: account, period: 3})
      assert [_] = all_enqueued(worker: TallyAccount)
    end)

    assert_received {^event, ^ref, %{accounts: 1}, %{periods: [1, 2, 3]}}
  end

  # The tally runs at the last season's end at the earliest, so its bonus is written
  # after earning has stopped. The tally takes its clock, as an operator's check does.
  test "the last season's bonus is added when it is tallied after the end" do
    # A start inside the wallet history the period-end snapshot reads.
    [coverage] = Ash.read!(RegentPoints.WalletCoverage, actor: Store.system())
    Application.put_env(:regent_points, :starts_at, coverage.starts_at)
    Application.put_env(:regent_points, :chain_client, Chain)
    Application.put_env(:regent_points, :test_stop, Rules.ends_at())
    account = person("0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower))
    award(account, DateTime.add(Rules.ends_at(), -@day))

    assert :ok =
             TallyAccount.tally(account, 3, Rules.program(), DateTime.add(Rules.ends_at(), 3600))

    # Three pieces held at the end: the 45% tier on the season's 5 points.
    assert [%{period: 3, earned_micro: 5_000_000, bonus_percent: 45, bonus_micro: 2_250_000}] =
             PeriodBonus
             |> Ash.Query.filter(account_id == ^account)
             |> Ash.read!(actor: Store.system())

    assert RegentPoints.summary!(actor: %{role: :human, human_account_id: account}).balance_micro ==
             7_250_000
  end

  # A start whose last season ended an hour ago; answers that end.
  defp ended do
    start = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -(90 * @day + 3600))
    Application.put_env(:regent_points, :starts_at, start)
    Rules.ends_at()
  end

  defp states(now) do
    seasons = Seasons.at(now)
    running = Enum.find(seasons, &(&1.state == :running))
    {Seasons.phase(seasons), Enum.map(seasons, & &1.state), running && running.days_left}
  end

  defp person(wallet \\ nil) do
    %{rows: [[id]]} =
      RegentPoints.Repo.query!(
        "INSERT INTO regent_names.platform_human_users (wallet_address) VALUES ($1) RETURNING id",
        [wallet]
      )

    id
  end

  # Saves the source's facts and records the action the way a site does.
  defp earn(rule_id, account, at) do
    key = "#{rule_id}:#{account}:#{DateTime.to_unix(at)}"
    put_facts(key, account, at)

    assert {:ok, _} =
             RegentPoints.record_event(reference(rule_id, key), actor: Store.system())
  end

  # An award dated inside the last season, checked and awarded as a site's queued
  # check awards it, for a season that has not happened yet.
  defp award(account, at) do
    rule = Enum.find(Rules.catalog(), &(&1["id"] == "patchbay.reply_published"))
    key = "late:#{account}"
    RegentPoints.open_account!(%{id: account}, actor: Store.system())

    event =
      RegentPoints.create_event!(
        Map.merge(facts(key, account, at), %{
          program_id: Rules.program(),
          rule_id: rule["id"],
          rule_snapshot: rule,
          award_key: Store.digest({key, rule["id"]}),
          payload_digest: Store.digest(key)
        }),
        actor: Store.system()
      )

    assert {:ok, %{status: :confirmed}} =
             RegentPoints.process_event(event.id, actor: Store.system())
  end

  defp put_facts(key, account, at) do
    saved = Application.get_env(:regent_points, :test_facts, %{})
    Application.put_env(:regent_points, :test_facts, Map.put(saved, key, facts(key, account, at)))
  end

  defp facts(key, account, at),
    do: %{
      source_app: "patchbay",
      source_kind: "test",
      source_event_key: key,
      account_id: account,
      actor_kind: "human",
      actor_id: to_string(account),
      source_action_at: at,
      qualified_at: at,
      evidence_ref: "test:" <> key,
      evidence: %{}
    }

  defp reference(rule_id, key),
    do: %{rule_id: rule_id, source_app: "patchbay", source_kind: "test", source_event_key: key}

  defp entries(account) do
    Entry
    |> Ash.Query.filter(account_id == ^account and program_id == ^Rules.program())
    |> Ash.Query.sort(recorded_at: :asc)
    |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
  end

  defp rejected(account) do
    for rejection <- RegentPoints.read_rejections!(actor: Store.system()),
        rejection.source["source_event_key"] =~ ":#{account}:",
        do: rejection.reason_code
  end
end

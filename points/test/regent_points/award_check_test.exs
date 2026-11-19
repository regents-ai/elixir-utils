defmodule RegentPoints.AwardCheckTest do
  # The source is asked at intake and again just before its award is written. The
  # intake check and the award run as separate jobs, as on a site, so a test can
  # change what the source says between them. On a real database.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: RegentPoints.Repo
  require Ash.Query
  alias RegentPoints.{Entry, IntakeWorker, Rules, Store, Worker}

  defmodule Source do
    @moduledoc false
    # Stands in for a site's check: it gives the answer a test set for the source as
    # it is now, and tells the test each time it is asked.
    def verify(%{"source_event_key" => key} = reference) do
      send(self(), {:asked, reference})
      Map.fetch!(Application.get_env(:regent_points, :test_answers, %{}), key)
    end
  end

  defmodule People do
    @moduledoc false
    @behaviour RegentPoints.Accounts

    @impl true
    def human(_id), do: %{wallet_address: nil, wallet_addresses: []}

    @impl true
    def agent_names(_id, _ids), do: {:ok, %{}}

    @impl true
    def people(_ids), do: {:ok, %{}}
  end

  @rule "account.activated"
  @start DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -3600)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentPoints.Repo)
    keys = [:program_id, :starts_at, :approved_rules, :adapters, :accounts, :test_answers]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    Application.put_env(:regent_points, :program_id, "award-check-test")
    Application.put_env(:regent_points, :starts_at, @start)
    Application.put_env(:regent_points, :approved_rules, [@rule])
    Application.put_env(:regent_points, :adapters, %{@rule => Source})
    Application.put_env(:regent_points, :accounts, People)
    account = person()
    {:ok, account: account, key: "account:#{account}"}
  end

  test "a source that accepts at intake and again at the award earns once", %{
    account: account,
    key: key
  } do
    answer(key, accepted(account, key))
    award = checked_at_intake(key)

    assert :ok = perform_job(Worker, award)
    # A second run of the award finds it written and asks nothing more.
    assert :ok = perform_job(Worker, award)

    assert [%{points_micro_delta: 25_000_000}] = entries(account)
    assert %{processing_status: :confirmed} = Store.event(award["event_id"])

    asked = reference(key)
    assert_received {:asked, ^asked}
    assert_received {:asked, ^asked}
    refute_received {:asked, _}
  end

  test "a source refused between intake and the award earns nothing", %{
    account: account,
    key: key
  } do
    answer(key, accepted(account, key))
    award = checked_at_intake(key)
    assert summary(account).pending == 1

    answer(key, {:error, :source_hidden})
    assert :ok = perform_job(Worker, award)

    assert entries(account) == []

    assert %{processing_status: :rejected, reason_code: "award_refused"} =
             Store.event(award["event_id"])

    assert %{pending: 0, balance_micro: 0} = summary(account)
    assert "source_hidden" in rejected(key)
  end

  test "a source that names another account at the award earns for neither account", %{
    account: account,
    key: key
  } do
    answer(key, accepted(account, key))
    award = checked_at_intake(key)

    other = person()
    answer(key, accepted(other, key))
    assert :ok = perform_job(Worker, award)

    assert entries(account) == []
    assert entries(other) == []

    assert %{processing_status: :rejected, reason_code: "award_refused"} =
             Store.event(award["event_id"])

    assert %{pending: 0, balance_micro: 0} = summary(account)
    assert summary(other).balance_micro == 0
    assert "account_changed" in rejected(key)
  end

  test "a source that names the same account at the award awards from the facts saved at intake",
       %{account: account, key: key} do
    answer(key, accepted(account, key))
    award = checked_at_intake(key)

    {:ok, facts} = accepted(account, key)
    later = DateTime.add(@start, 120)
    answer(key, {:ok, %{facts | source_action_at: later, qualified_at: later}})
    assert :ok = perform_job(Worker, award)

    assert [%{points_micro_delta: 25_000_000, earned_at: earned}] = entries(account)
    assert DateTime.compare(earned, DateTime.add(@start, 60)) == :eq
  end

  test "a source that cannot answer at the award is asked again on the next run", %{
    account: account,
    key: key
  } do
    answer(key, accepted(account, key))
    award = checked_at_intake(key)

    answer(key, {:retry, :source_unavailable})
    assert {:error, _} = perform_job(Worker, award, attempt: 1)

    assert entries(account) == []
    assert %{processing_status: :pending} = Store.event(award["event_id"])
    assert summary(account).pending == 1

    answer(key, accepted(account, key))
    assert :ok = perform_job(Worker, award, attempt: 2)

    assert [%{points_micro_delta: 25_000_000}] = entries(account)
    assert %{pending: 0, balance_micro: 25_000_000} = summary(account)
  end

  test "an award checked twice can still be corrected", %{account: account, key: key} do
    answer(key, accepted(account, key))
    assert :ok = perform_job(Worker, checked_at_intake(key))
    [original] = entries(account)

    RegentPoints.reverse!(original.id, "source-hidden", 25_000_000, "source_hidden",
      actor: Store.system()
    )

    assert [%{points_micro_delta: 25_000_000}, %{points_micro_delta: -25_000_000}] =
             entries(account)

    assert summary(account).balance_micro == 0
  end

  # The intake check alone: the award it queues waits, as on a site, until the test
  # runs it. Returns that award job's arguments.
  defp checked_at_intake(key) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = perform_job(IntakeWorker, reference(key))
    end)

    [%{args: args}] = all_enqueued(worker: Worker)
    args
  end

  defp answer(key, answer) do
    answers = Application.get_env(:regent_points, :test_answers, %{})
    Application.put_env(:regent_points, :test_answers, Map.put(answers, key, answer))
  end

  defp accepted(account, key) do
    at = DateTime.add(@start, 60)

    {:ok,
     %{
       source_app: "site-a",
       source_kind: "test",
       source_event_key: key,
       account_id: account,
       actor_kind: "human",
       actor_id: to_string(account),
       source_action_at: at,
       qualified_at: at,
       evidence_ref: "test:" <> key,
       evidence: %{}
     }}
  end

  defp reference(key),
    do: %{
      "rule_id" => @rule,
      "source_app" => "site-a",
      "source_kind" => "test",
      "source_event_key" => key
    }

  defp person do
    %{rows: [[id]]} =
      RegentPoints.Repo.query!(
        "INSERT INTO regent_names.platform_human_users DEFAULT VALUES RETURNING id"
      )

    id
  end

  defp summary(account),
    do: RegentPoints.summary!(actor: %{role: :human, human_account_id: account})

  defp entries(account) do
    Entry
    |> Ash.Query.filter(account_id == ^account and program_id == ^Rules.program())
    |> Ash.Query.sort(recorded_at: :asc)
    |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
  end

  defp rejected(key) do
    for rejection <- RegentPoints.read_rejections!(actor: Store.system()),
        rejection.source["source_event_key"] == key,
        do: rejection.reason_code
  end
end

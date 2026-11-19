defmodule RegentPoints.OfferedAgainTest do
  # A linked social account's one-time award when the link changes while its award
  # waits: replaced, let go and linked again, or moved to another person. The intake
  # check runs when a test offers the link and the awards when a test runs them, as
  # separate jobs on a site. On a real database.
  use ExUnit.Case, async: false
  use ExUnitProperties
  use Oban.Testing, repo: RegentPoints.Repo
  require Ash.Query
  alias RegentPoints.{Entry, Event, IntakeWorker, Rules, Store, Worker}

  defmodule Links do
    @moduledoc false
    # Stands in for each site's check of a linked social account: it answers for the
    # link as a test last set it on that site, keyed by provider and subject.
    def verify(%{"source_app" => app, "source_event_key" => key}) do
      case Map.fetch(Application.get_env(:regent_points, :test_links, %{}), {app, key}) do
        {:ok, :unreachable} ->
          {:retry, :source_unreachable}

        {:ok, {account, at}} ->
          {:ok,
           %{
             source_app: app,
             source_kind: "linked_identity",
             source_event_key: key,
             account_id: account,
             actor_kind: "human",
             actor_id: to_string(account),
             source_action_at: at,
             qualified_at: at,
             evidence_ref: "link:" <> key,
             evidence: %{"subject_key" => key}
           }}

        :error ->
          {:error, :link_not_found}
      end
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

  @rule "social.x"
  @start DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -3600)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentPoints.Repo)
    keys = [:program_id, :starts_at, :approved_rules, :adapters, :accounts, :test_links]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    Application.put_env(:regent_points, :program_id, "offered-again-test")
    Application.put_env(:regent_points, :starts_at, @start)
    Application.put_env(:regent_points, :approved_rules, [@rule])
    Application.put_env(:regent_points, :adapters, %{@rule => Links})
    Application.put_env(:regent_points, :accounts, People)
    Application.put_env(:regent_points, :test_links, %{})
    :ok
  end

  test "an X account replaced while its award waits on a retry: the replacement earns, once" do
    account = person()
    [first, second] = [subject(), subject()]

    Oban.Testing.with_testing_mode(:manual, fn ->
      link(first, account, 1)
      offer(first)

      # The first award cannot get an answer; Oban will try it again.
      set(first, :unreachable)
      assert %{failure: 1} = run_awards()

      # Meanwhile the person links a different X account, and it is offered.
      unlink(first)
      link(second, account, 2)
      offer(second)
      assert %{success: 1, failure: 0} = run_awards()

      # The first award's retry is refused: the first X account is gone.
      assert %{success: 1, failure: 0} = run_awards(with_scheduled: true)
    end)

    assert [%{points_micro_delta: 10_000_000, earned_at: earned}] = entries(account)
    assert DateTime.compare(earned, at(2)) == :eq
    assert status(first) == :rejected
    assert status(second) == :confirmed
  end

  test "an X account let go while its award waits, and linked again later, earns once" do
    account = person()
    x = subject()

    Oban.Testing.with_testing_mode(:manual, fn ->
      link(x, account, 1)
      offer(x)
      unlink(x)
      assert %{success: 1} = run_awards()
      assert status(x) == :rejected

      link(x, account, 3)
      offer(x)
      assert %{processing_status: :pending, reason_code: nil, processed_at: nil} = event(x)
      assert summary(account).pending == 1
      assert %{success: 1, failure: 0} = run_awards()

      # Offered once more, it earns nothing more.
      offer(x)
      assert %{failure: 0} = run_awards()
    end)

    assert [%{points_micro_delta: 10_000_000, earned_at: earned}] = entries(account)
    assert DateTime.compare(earned, at(3)) == :eq
    assert %{processing_status: :confirmed, reason_code: "qualified"} = event(x)
  end

  test "an award whose last attempt gets no answer ends award_failed, and the link offered again earns" do
    account = person()
    x = subject()

    Oban.Testing.with_testing_mode(:manual, fn ->
      link(x, account, 1)
      offer(x)
      [award] = all_enqueued(worker: Worker)
      set(x, :unreachable)

      # Nine attempts have gone by; this run is the last.
      RegentPoints.Repo.query!("UPDATE oban_jobs SET attempt = 9 WHERE id = $1", [award.id])
      assert %{discard: 1} = run_awards()
      assert %{processing_status: :rejected, reason_code: "award_failed"} = event(x)
      assert summary(account).pending == 0

      link(x, account, 2)
      offer(x)
      assert %{success: 1, failure: 0} = run_awards()
    end)

    assert [%{points_micro_delta: 10_000_000}] = entries(account)
  end

  test "an X account moved to another person while its award waits earns for the one who holds it" do
    [before, holder] = [person(), person()]
    x = subject()

    Oban.Testing.with_testing_mode(:manual, fn ->
      link(x, before, 1)
      offer(x)
      link(x, holder, 2)
      assert %{success: 1} = run_awards()

      offer(x)
      assert %{success: 1, failure: 0} = run_awards()
    end)

    assert entries(before) == []
    assert [%{points_micro_delta: 10_000_000}] = entries(holder)
    assert %{account_id: ^holder, processing_status: :confirmed} = event(x)
  end

  test "a link offered again while the run that refused it is still finishing gets its own award" do
    account = person()
    x = subject()

    Oban.Testing.with_testing_mode(:manual, fn ->
      link(x, account, 1)
      offer(x)
      [refusing] = all_enqueued(worker: Worker)
      unlink(x)
      assert %{success: 1} = run_awards()

      # The refusing run has saved its answer, but Oban has not yet marked it done.
      RegentPoints.Repo.query!("UPDATE oban_jobs SET state = 'executing' WHERE id = $1", [
        refusing.id
      ])

      link(x, account, 2)
      offer(x)
      assert [%{id: id}] = all_enqueued(worker: Worker)
      refute id == refusing.id
      assert %{success: 1, failure: 0} = run_awards()
    end)

    assert [%{points_micro_delta: 10_000_000}] = entries(account)
  end

  # Orders of up to eight steps over two people, two X accounts and two sites, ending
  # with the awards: the first person links the first or second X account here, the
  # second person links the first here or on the other site, the first X account is
  # let go here, or the waiting awards run. Each link is offered as it is made.
  # Whatever the order, one X account earns at most once and one person earns the
  # rule at most once.
  @steps [
    {:link, :a, :one, "site-a"},
    {:link, :b, :one, "site-a"},
    {:link, :b, :one, "site-b"},
    {:link, :a, :two, "site-a"},
    {:unlink, :one, "site-a"},
    :awards
  ]

  property "no order of offers, refusals and offers made again earns twice for one X account or one person" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      check all(steps <- list_of(member_of(@steps), min_length: 1, max_length: 8), max_runs: 150) do
        people = %{a: person(), b: person()}
        subjects = %{one: subject(), two: subject()}

        (steps ++ [:awards])
        |> Enum.with_index(1)
        |> Enum.each(fn {step, n} -> take(step, n, people, subjects) end)

        earned = Enum.flat_map(Map.values(people), &entries/1)
        assert Enum.uniq_by(earned, & &1.account_id) == earned
        keys = Enum.map(earned, &Store.event(&1.event_id).source_event_key)
        assert Enum.uniq(keys) == keys
      end
    end)
  end

  defp take({:link, who, which, app}, n, people, subjects) do
    link(subjects[which], people[who], n, app)
    offer(subjects[which], app)
  end

  defp take({:unlink, which, app}, _n, _people, subjects), do: unlink(subjects[which], app)
  defp take(:awards, _n, _people, _subjects), do: assert(%{failure: 0} = run_awards())

  defp subject, do: "x-" <> Ecto.UUID.generate()
  defp at(n), do: DateTime.add(@start, n)
  defp link(subject, account, n, app \\ "site-a"), do: set(subject, {account, at(n)}, app)

  defp set(subject, answer, app \\ "site-a") do
    links = Application.get_env(:regent_points, :test_links)

    Application.put_env(
      :regent_points,
      :test_links,
      Map.put(links, {app, "x:" <> subject}, answer)
    )
  end

  defp unlink(subject, app \\ "site-a") do
    links = Application.get_env(:regent_points, :test_links)
    Application.put_env(:regent_points, :test_links, Map.delete(links, {app, "x:" <> subject}))
  end

  # The intake check of one offer; the award it queues waits until awards run.
  defp offer(subject, app \\ "site-a") do
    assert :ok =
             perform_job(IntakeWorker, %{
               "rule_id" => @rule,
               "source_app" => app,
               "source_kind" => "linked_identity",
               "source_event_key" => "x:" <> subject
             })
  end

  defp run_awards(opts \\ []), do: Oban.drain_queue([queue: :points] ++ opts)

  defp event(subject) do
    Event
    |> Ash.Query.filter(
      program_id == ^Rules.program() and source_app == "site-a" and
        source_event_key == ^("x:" <> subject)
    )
    |> Ash.read_one!(actor: Store.system())
  end

  defp status(subject), do: event(subject).processing_status

  defp summary(account),
    do: RegentPoints.summary!(actor: %{role: :human, human_account_id: account})

  defp person do
    %{rows: [[id]]} =
      RegentPoints.Repo.query!(
        "INSERT INTO regent_names.platform_human_users DEFAULT VALUES RETURNING id"
      )

    id
  end

  defp entries(account) do
    Entry
    |> Ash.Query.filter(account_id == ^account and program_id == ^Rules.program())
    |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
  end
end

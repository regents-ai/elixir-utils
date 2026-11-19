defmodule RegentPoints.StartAndVersionsTest do
  # Records actions through record_event, the source check and the award, on a real
  # database, with Oban running each job as it is queued.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: RegentPoints.Repo
  require Ash.Query
  alias RegentPoints.{Entry, IntakeWorker, Rules, StartAwards, Store, Worker}

  defmodule Source do
    @moduledoc false
    # Stands in for a site's checkers: it answers from the facts a test saved, and
    # lists, as `existing/2`, the start-rule state a test says is there, dated before
    # the moment it is asked about.
    def verify(%{"source_event_key" => key}),
      do: Map.fetch(Application.get_env(:regent_points, :test_facts, %{}), key)

    def existing(rule_id, at) do
      facts = Application.get_env(:regent_points, :test_facts, %{})

      for {account, %{rule_id: ^rule_id} = reference} <-
            Application.get_env(:regent_points, :test_existing, []),
          DateTime.before?(facts[reference.source_event_key].source_action_at, at),
          do: {account, Map.delete(reference, :rule_id)}
    end
  end

  @rules ~w(account.activated social.x agent.activated patchbay.reply_published template.first_agent_note)
  @start DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -3600)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentPoints.Repo)
    keys = [:program_id, :starts_at, :approved_rules, :adapters, :test_facts, :test_existing]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    Application.put_env(:regent_points, :program_id, "start-and-versions-test")
    Application.put_env(:regent_points, :starts_at, @start)
    Application.put_env(:regent_points, :approved_rules, @rules -- ["template.first_agent_note"])
    Application.put_env(:regent_points, :adapters, Map.new(@rules, &{&1, Source}))
    :ok
  end

  test "a one-time rule earned under version 1 earns nothing under version 2" do
    account = person()
    earn("account.activated", account, "account:#{account}", after_start(60))
    assert [%{rule_version: 1, points_micro_delta: 25_000_000}] = entries(account)

    # The rule's next version, with its id unchanged: the account already has its one award.
    v2 = Rules.catalog() |> rule("account.activated") |> Map.put("version", 2)

    assert %{status: :capped} =
             award_under(v2, account, "account-again:#{account}", after_start(120), "site-a")

    assert [%{rule_version: 1, points_micro_delta: 25_000_000}] = entries(account)
  end

  test "a daily rule's count carries across a version change inside one UTC day" do
    account = person()
    # Both replies in the same second, so they always fall in one UTC day.
    at = after_start(60)
    earn("patchbay.reply_published", account, "reply-1:#{account}", at, %{}, "patchbay")

    v2 = Rules.catalog() |> rule("patchbay.reply_published") |> Map.put("version", 2)
    award_under(v2, account, "reply-2:#{account}", at, "patchbay")

    # Once a day: the second reply, under version 2, writes a 0-point entry that
    # shows the reduction; each entry keeps the version it was earned under.
    assert [
             %{rule_version: 1, points_micro_delta: 5_000_000},
             %{rule_version: 2, points_micro_delta: 0}
           ] =
             entries(account)
  end

  test "what an account had before the start earns at the start, without the person doing anything" do
    account = person()
    before = DateTime.add(@start, -86_400)
    existing(account, "account.activated", "account:#{account}", before)
    existing(account, "social.x", "x:#{account}", before, %{"subject_key" => "x:#{account}"})
    existing(account, "agent.activated", "pairing:#{account}", before, agent: true)

    assert :ok = StartAwards.perform(%Oban.Job{})

    assert [
             %{rule_id: "account.activated", points_micro_delta: 25_000_000},
             %{rule_id: "agent.activated", points_micro_delta: 25_000_000},
             %{rule_id: "social.x", points_micro_delta: 10_000_000}
           ] = entries(account) |> Enum.sort_by(& &1.rule_id)

    assert Enum.all?(entries(account), &(DateTime.compare(&1.earned_at, @start) == :eq))
  end

  test "a social linked after the start, before the job first runs, earns once" do
    account = person()
    linked = after_start(30)
    earn("social.x", account, "x:#{account}", linked, %{"subject_key" => "x:#{account}"})
    # The site's list still shows the link when the job runs.
    Application.put_env(:regent_points, :test_existing, [
      {account, reference("social.x", "x:#{account}")}
    ])

    assert :ok = StartAwards.perform(%Oban.Job{})

    assert [%{rule_id: "social.x", earned_at: earned, points_micro_delta: 10_000_000}] =
             entries(account)

    assert DateTime.compare(earned, linked) == :eq
  end

  test "what came after the start, before a site turned Points on, earns at its real time" do
    account = person()
    joined = DateTime.add(@start, -86_400)
    linked = after_start(600)
    existing(account, "account.activated", "account:#{account}", joined)
    existing(account, "social.x", "x:#{account}", linked, %{"subject_key" => "x:#{account}"})

    assert :ok = StartAwards.perform(%Oban.Job{})

    assert [
             %{rule_id: "account.activated", earned_at: at_start},
             %{rule_id: "social.x", earned_at: at_link}
           ] = entries(account) |> Enum.sort_by(& &1.rule_id)

    assert DateTime.compare(at_start, @start) == :eq
    assert DateTime.compare(at_link, linked) == :eq
  end

  test "an account a listener already recorded for the rule is not offered again" do
    account = person()
    linked = after_start(60)
    subject = %{"subject_key" => "x:#{account}"}
    earn("social.x", account, "x-listener:#{account}", linked, subject)
    # The run's source names the same link under its own key.
    existing(account, "social.x", "x-run:#{account}", linked, subject)

    assert :ok = StartAwards.perform(%Oban.Job{})

    assert [_one] = events(account)
    assert [%{rule_id: "social.x", points_micro_delta: 10_000_000}] = entries(account)
  end

  test "the same state offered by the run and by a listener earns once" do
    account = person()
    paired = after_start(120)
    existing(account, "agent.activated", "pairing:#{account}", paired, agent: true)

    assert :ok = StartAwards.perform(%Oban.Job{})

    assert {:ok, _} =
             RegentPoints.record_event(reference("agent.activated", "pairing:#{account}"),
               actor: Store.system()
             )

    assert [_one] = events(account)
    assert [%{rule_id: "agent.activated", earned_at: earned}] = entries(account)
    assert DateTime.compare(earned, paired) == :eq
  end

  test "two sites running the job for one account give one award per rule" do
    account = person()
    before = DateTime.add(@start, -86_400)
    # The account is one Regents account on every site; each site has its own pairing.
    existing(account, "account.activated", "account:#{account}", before)
    existing(account, "agent.activated", "pairing-site-a:#{account}", before, agent: true)

    existing(account, "agent.activated", "pairing-site-b:#{account}", before,
      agent: true,
      app: "site-b"
    )

    assert :ok = StartAwards.perform(%Oban.Job{})
    assert :ok = StartAwards.perform(%Oban.Job{})

    assert [%{rule_id: "account.activated"}, %{rule_id: "agent.activated"}] =
             entries(account) |> Enum.sort_by(& &1.rule_id)
  end

  test "a second run records nothing more" do
    account = person()
    before = DateTime.add(@start, -86_400)
    existing(account, "account.activated", "account:#{account}", before)
    existing(account, "agent.activated", "pairing:#{account}", before, agent: true)

    assert :ok = StartAwards.perform(%Oban.Job{})
    first = events(account)
    assert length(first) == 2

    # Each record is an offer to the intake; the second run makes none.
    test = self()
    handler = "start-awards-offers-#{account}"

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :job, :start],
        fn _, _, %{job: job}, _ ->
          send(test, {:offered, job.worker})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert :ok = StartAwards.perform(%Oban.Job{})
    refute_received {:offered, "RegentPoints.IntakeWorker"}
    assert events(account) == first
  end

  test "the start run's checks and awards wait behind live ones" do
    started = person()
    live = person()
    before = DateTime.add(@start, -86_400)
    existing(started, "account.activated", "account:#{started}", before)
    put_facts("account:#{live}", facts(live, "account:#{live}", after_start(60), %{}, []))

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = StartAwards.perform(%Oban.Job{})

      assert {:ok, _} =
               RegentPoints.record_event(reference("account.activated", "account:#{live}"),
                 actor: Store.system()
               )

      checks = all_enqueued(worker: IntakeWorker)
      assert priority(checks, "account:#{started}") > priority(checks, "account:#{live}")

      for %{args: args, priority: priority} <- checks,
          do: assert(:ok = perform_job(IntakeWorker, args, priority: priority))

      awards = all_enqueued(worker: Worker)
      assert length(awards) == 2

      assert Enum.sort(Enum.map(awards, & &1.priority)) ==
               Enum.sort(Enum.map(checks, & &1.priority))
    end)
  end

  test "a start run performed twice before its checks run queues each candidate once" do
    account = person()
    before = DateTime.add(@start, -86_400)
    existing(account, "account.activated", "account:#{account}", before)
    existing(account, "agent.activated", "pairing:#{account}", before, agent: true)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = StartAwards.perform(%Oban.Job{})
      assert :ok = StartAwards.perform(%Oban.Job{})

      assert ["account:#{account}", "pairing:#{account}"] ==
               all_enqueued(worker: IntakeWorker)
               |> Enum.map(& &1.args["source_event_key"])
               |> Enum.sort()
    end)
  end

  test "an account whose only event for a start rule was refused is offered again and earns once" do
    account = person()
    other = person()
    key = "account:#{account}"
    before = DateTime.add(@start, -86_400)
    existing(account, "account.activated", key, before)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = StartAwards.perform(%Oban.Job{})
      run_checks()
      # By the award the source names another account, so the award is refused.
      put_facts(key, facts(other, key, before, %{}, []))
      run_awards()
    end)

    assert [:rejected] = statuses(account)
    put_facts(key, facts(account, key, before, %{}, []))

    assert :ok = StartAwards.perform(%Oban.Job{})
    assert :ok = StartAwards.perform(%Oban.Job{})
    assert [:confirmed] = statuses(account)
    assert [%{rule_id: "account.activated", points_micro_delta: 25_000_000}] = entries(account)
  end

  for status <- [:confirmed, :capped] do
    test "an account whose event for a start rule ended #{status} is not offered again" do
      account = person()
      existing(account, "account.activated", "account:#{account}", DateTime.add(@start, -60))

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = StartAwards.perform(%Oban.Job{})
        run_checks()

        for event <- read_events(account),
            do:
              RegentPoints.finish_event!(event, %{processing_status: unquote(status)},
                actor: Store.system()
              )

        assert :ok = StartAwards.perform(%Oban.Job{})
        assert [] = all_enqueued(worker: IntakeWorker)
      end)
    end
  end

  test "a waiting event whose award job is gone gets one from the next start run and earns once" do
    account = person()
    existing(account, "account.activated", "account:#{account}", DateTime.add(@start, -60))

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = StartAwards.perform(%Oban.Job{})
      run_checks()
      assert [_award] = all_enqueued(worker: Worker)
      drop_jobs(Worker)
    end)

    assert [:pending] = statuses(account)
    assert :ok = StartAwards.perform(%Oban.Job{})
    assert :ok = StartAwards.perform(%Oban.Job{})
    assert [:confirmed] = statuses(account)
    assert [%{points_micro_delta: 25_000_000}] = entries(account)
  end

  test "a waiting event whose award job still waits gets no second one" do
    account = person()
    existing(account, "account.activated", "account:#{account}", DateTime.add(@start, -60))

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = StartAwards.perform(%Oban.Job{})
      run_checks()
      assert :ok = StartAwards.perform(%Oban.Job{})
      run_checks()
      assert [_one] = all_enqueued(worker: Worker)
    end)
  end

  test "a subject whose waiting event is offered for a second account earns only for the second" do
    first = person()
    second = person()
    key = "x:subject-#{first}"
    subject = %{"subject_key" => key}
    linked = after_start(60)
    existing(first, "social.x", key, linked, subject)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = StartAwards.perform(%Oban.Job{})
      run_checks()
      drop_jobs(Worker)
    end)

    # The X account is linked to the second account now, under the same source key.
    put_facts(key, facts(second, key, after_start(120), subject, []))
    Application.put_env(:regent_points, :test_existing, [{second, reference("social.x", key)}])

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _} =
               RegentPoints.record_event(reference("social.x", key), actor: Store.system())

      run_checks()
      assert [%{reason_code: "source_identity_conflict"}] = rejections(key)
      run_awards()
    end)

    assert [%{account_id: ^first, processing_status: :rejected}] = read_events(first)

    assert :ok = StartAwards.perform(%Oban.Job{})
    assert :ok = StartAwards.perform(%Oban.Job{})
    assert entries(first) == []
    assert [%{rule_id: "social.x", points_micro_delta: 10_000_000}] = entries(second)
  end

  test "a start rule off the approved list earns nothing at the start" do
    account = person()

    existing(account, "social.x", "x:#{account}", DateTime.add(@start, -60), %{
      "subject_key" => "x:#{account}"
    })

    Application.put_env(:regent_points, :approved_rules, ["account.activated"])

    assert :ok = StartAwards.perform(%Oban.Job{})
    assert entries(account) == []
  end

  test "the job waits for the start, and stops while there is none" do
    Application.put_env(:regent_points, :starts_at, DateTime.add(DateTime.utc_now(), 600))
    assert {:snooze, wait} = StartAwards.perform(%Oban.Job{})
    assert wait in 590..600

    Application.put_env(:regent_points, :starts_at, nil)
    assert {:cancel, :not_started} = StartAwards.perform(%Oban.Job{})
  end

  test "the approved list is the one switch for what a site earns" do
    assert Enum.map(Rules.tracked(), & &1["id"]) |> Enum.sort() ==
             Enum.sort(@rules -- ["template.first_agent_note"])

    Application.put_env(:regent_points, :approved_rules, [])
    assert Rules.tracked() == []
    assert Rules.active() == []
  end

  defp person do
    %{rows: [[id]]} =
      RegentPoints.Repo.query!(
        "INSERT INTO regent_names.platform_human_users DEFAULT VALUES RETURNING id"
      )

    id
  end

  defp after_start(seconds), do: DateTime.add(@start, seconds)

  # Saves the source's facts and records the action the way a site does.
  defp earn(rule_id, account, key, at, evidence \\ %{}, app \\ "site-a") do
    put_facts(key, facts(account, key, at, evidence, app: app))

    assert {:ok, _} =
             RegentPoints.record_event(reference(rule_id, key, app), actor: Store.system())
  end

  defp existing(account, rule_id, key, at, opts \\ [])

  defp existing(account, rule_id, key, at, %{} = evidence),
    do: existing(account, rule_id, key, at, evidence: evidence)

  defp existing(account, rule_id, key, at, opts) do
    evidence = Keyword.get(opts, :evidence, %{})
    put_facts(key, facts(account, key, at, evidence, opts))
    listed = Application.get_env(:regent_points, :test_existing, [])

    Application.put_env(:regent_points, :test_existing, [
      {account, reference(rule_id, key, Keyword.get(opts, :app, "site-a"))} | listed
    ])
  end

  # Version 2 of a rule pinned on a new event, as intake pins it once the catalog moves on.
  defp award_under(rule, account, key, at, app) do
    facts = facts(account, key, at, %{}, app: app)
    put_facts(key, facts)
    RegentPoints.open_account!(%{id: account}, actor: Store.system())

    event =
      RegentPoints.create_event!(
        Map.merge(
          Map.take(facts, [
            :source_app,
            :source_kind,
            :source_event_key,
            :account_id,
            :actor_kind,
            :actor_id,
            :source_action_at,
            :qualified_at,
            :evidence_ref,
            :evidence
          ]),
          %{
            program_id: Rules.program(),
            rule_id: rule["id"],
            rule_snapshot: Map.put(rule, "effective_at", DateTime.to_iso8601(@start)),
            award_key: Store.digest({key, rule["id"]}),
            payload_digest: Store.digest(facts)
          }
        ),
        actor: Store.system()
      )

    {:ok, result} = RegentPoints.process_event(event.id, actor: Store.system())
    result
  end

  defp facts(account, key, at, evidence, opts) do
    evidence =
      if Keyword.get(opts, :agent),
        do: Map.put(evidence, "attribution_link_id", key),
        else: evidence

    %{
      source_app: Keyword.get(opts, :app, "site-a"),
      source_kind: "test",
      source_event_key: key,
      account_id: account,
      actor_kind: if(Keyword.get(opts, :agent), do: "agent", else: "human"),
      actor_id: to_string(account),
      source_action_at: at,
      qualified_at: at,
      evidence_ref: "test:" <> key,
      evidence: evidence
    }
  end

  defp put_facts(key, facts) do
    saved = Application.get_env(:regent_points, :test_facts, %{})
    Application.put_env(:regent_points, :test_facts, Map.put(saved, key, facts))
  end

  defp reference(rule_id, key, app \\ "site-a"),
    do: %{rule_id: rule_id, source_app: app, source_kind: "test", source_event_key: key}

  # Runs each waiting job as Oban would, and marks it done.
  defp run_checks, do: run_jobs(IntakeWorker)
  defp run_awards, do: run_jobs(Worker)

  defp run_jobs(worker) do
    for %{args: args, priority: priority} <- all_enqueued(worker: worker),
        do: assert(:ok = perform_job(worker, args, priority: priority))

    set_done(worker)
  end

  defp set_done(worker),
    do:
      Oban.Job |> where_worker(worker) |> RegentPoints.Repo.update_all(set: [state: "completed"])

  defp drop_jobs(worker), do: Oban.Job |> where_worker(worker) |> RegentPoints.Repo.delete_all()

  defp where_worker(query, worker) do
    name = inspect(worker)
    import Ecto.Query, only: [where: 3]
    where(query, [j], j.worker == ^name and j.state == "available")
  end

  defp read_events(account) do
    RegentPoints.Event
    |> Ash.Query.filter(account_id == ^account and program_id == ^Rules.program())
    |> Ash.read!(actor: Store.system())
  end

  defp statuses(account), do: Enum.map(read_events(account), & &1.processing_status)

  defp rejections(key) do
    RegentPoints.read_rejections!(actor: Store.system())
    |> Enum.filter(&(&1.source["source_event_key"] == key))
  end

  defp priority(jobs, key),
    do: Enum.find(jobs, &(&1.args["source_event_key"] == key)).priority

  defp rule(catalog, id), do: Enum.find(catalog, &(&1["id"] == id))

  defp events(account) do
    RegentPoints.Event
    |> Ash.Query.filter(account_id == ^account and program_id == ^Rules.program())
    |> Ash.Query.sort(:id)
    |> Ash.read!(actor: Store.system())
    |> Enum.map(& &1.id)
  end

  defp entries(account) do
    Entry
    |> Ash.Query.filter(account_id == ^account and program_id == ^Rules.program())
    |> Ash.Query.sort(earned_at: :asc, recorded_at: :asc)
    |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
  end
end

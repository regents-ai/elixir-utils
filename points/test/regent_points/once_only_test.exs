defmodule RegentPoints.OnceOnlyTest do
  # Invariant: a one-time award earns once for an account, whichever site records
  # it, and whether it is recorded at the start or live. A linked social account
  # earns once ever, whichever account links it; a person's first paired agent
  # earns once however often they pair. Each site records through record_event,
  # its source check and the award, on a real database, with Oban running each job
  # as it is queued.
  use ExUnit.Case, async: false
  require Ash.Query
  alias RegentPoints.{Entry, Event, Rules, StartAwards, Store}

  defmodule Source do
    @moduledoc false
    # Stands in for every site's checks: it answers from the facts a test saved
    # for one site, and lists, as `existing/2`, what the site whose start job is
    # running had before the start.
    def verify(%{"source_app" => site, "source_event_key" => key}),
      do: Map.fetch(Application.get_env(:regent_points, :test_facts, %{}), {site, key})

    def existing(rule_id, _start) do
      for {account, %{rule_id: ^rule_id} = reference} <-
            Application.get_env(:regent_points, :test_existing, []),
          do: {account, Map.delete(reference, :rule_id)}
    end
  end

  @rules ~w(social.x agent.activated)
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

    Application.put_env(:regent_points, :program_id, "once-only-test")
    Application.put_env(:regent_points, :starts_at, @start)
    Application.put_env(:regent_points, :approved_rules, @rules)
    Application.put_env(:regent_points, :adapters, Map.new(@rules, &{&1, Source}))
    :ok
  end

  describe "a linked X account" do
    test "linked live earns once, whichever site records it and whichever account links it" do
      [person, other] = [person(), person()]
      x = unique("x")

      live("site-a", x_link(person, x), after_start(60))
      # The same person and X account on a second site: nothing more is recorded.
      live("site-b", x_link(person, x), after_start(120))

      assert points(person, "social.x") == [10_000_000]
      assert events(person, "social.x") == [{"site-a", :confirmed, "qualified"}]

      # Another person links the same X account on a third site: recorded, and
      # held to nothing because that X account has had its award.
      live("site-c", x_link(other, x), after_start(180))

      assert points(other, "social.x") == []
      assert events(other, "social.x") == [{"site-c", :capped, "allowance_used"}]
    end

    test "linked before the start earns once, whichever sites list it at the start" do
      [person, other] = [person(), person()]
      x = unique("x")

      start_job("site-a", [x_link(person, x)])
      start_job("site-b", [x_link(person, x)])
      start_job("site-c", [x_link(other, x)])

      assert points(person, "social.x") == [10_000_000]
      assert events(person, "social.x") == [{"site-a", :confirmed, "qualified"}]
      assert points(other, "social.x") == []
      assert events(other, "social.x") == [{"site-c", :capped, "allowance_used"}]
    end

    test "awarded at one site's start earns nothing more live on another, and the other way round" do
      [early, late] = [person(), person()]
      [x, other_x, late_x] = [unique("x"), unique("x"), unique("x")]

      # Linked live on site B after the start, before site A's start job ran.
      live("site-b", x_link(late, late_x), after_start(30))
      start_job("site-a", [x_link(early, x), x_link(late, late_x)])
      # After site A's start award: the same X account, then a different one, on site B.
      live("site-b", x_link(early, x), after_start(60))
      live("site-b", x_link(early, other_x), after_start(120))

      assert points(early, "social.x") == [10_000_000]
      assert events(early, "social.x") == [{"site-a", :confirmed, "qualified"}]
      assert points(late, "social.x") == [10_000_000]
      assert events(late, "social.x") == [{"site-b", :confirmed, "qualified"}]
    end
  end

  describe "a paired agent" do
    test "pairing again, or pairing another agent, on any site earns the first-agent award once" do
      person = person()

      live("site-a", pairing(person), after_start(60))
      # Unpaired and paired again: a new pairing on the same site.
      live("site-a", pairing(person), after_start(120))
      # Another agent, paired on another site.
      live("site-b", pairing(person), after_start(180))

      assert points(person, "agent.activated") == [25_000_000]
      assert events(person, "agent.activated") == [{"site-a", :confirmed, "qualified"}]
    end

    test "paired before the start earns once, whichever sites list it at the start" do
      person = person()

      start_job("site-a", [pairing(person)])
      start_job("site-b", [pairing(person)])

      assert points(person, "agent.activated") == [25_000_000]
      assert events(person, "agent.activated") == [{"site-a", :confirmed, "qualified"}]
    end

    test "awarded at one site's start earns nothing more live on another, and the other way round" do
      [early, late] = [person(), person()]

      # Paired live on site B after the start, before site A's start job ran.
      live("site-b", pairing(late), after_start(30))
      start_job("site-a", [pairing(early), pairing(late)])
      live("site-b", pairing(early), after_start(60))

      assert points(early, "agent.activated") == [25_000_000]
      assert events(early, "agent.activated") == [{"site-a", :confirmed, "qualified"}]
      assert points(late, "agent.activated") == [25_000_000]
      assert events(late, "agent.activated") == [{"site-b", :confirmed, "qualified"}]
    end
  end

  defp person do
    %{rows: [[id]]} =
      RegentPoints.Repo.query!(
        "INSERT INTO regent_names.platform_human_users DEFAULT VALUES RETURNING id"
      )

    id
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
  defp after_start(seconds), do: DateTime.add(@start, seconds)

  defp x_link(account, x) do
    key = "x:" <> x

    %{
      rule_id: "social.x",
      source_kind: "linked_identity",
      source_event_key: key,
      account_id: account,
      actor_kind: "human",
      actor_id: to_string(account),
      evidence: %{"subject_key" => key}
    }
  end

  defp pairing(account) do
    id = unique("pairing")

    %{
      rule_id: "agent.activated",
      source_kind: "pairing",
      source_event_key: id,
      account_id: account,
      actor_kind: "agent",
      actor_id: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower),
      evidence: %{"attribution_link_id" => id}
    }
  end

  # A site records an action the way it does live.
  defp live(site, action, at) do
    assert {:ok, _} = RegentPoints.record_event(save(site, action, at), actor: Store.system())
  end

  # A site's start job, listing what the site had a day before the start.
  defp start_job(site, actions) do
    listed = for action <- actions, do: {action.account_id, save(site, action, day_before())}
    Application.put_env(:regent_points, :test_existing, listed)
    assert :ok = StartAwards.perform(%Oban.Job{})
  end

  defp day_before, do: DateTime.add(@start, -86_400)

  # Saves what the site's source check answers for the action, and returns the
  # reference the site offers.
  defp save(site, action, at) do
    facts =
      action
      |> Map.take([:source_kind, :source_event_key, :account_id, :actor_kind, :actor_id])
      |> Map.merge(%{
        source_app: site,
        source_action_at: at,
        qualified_at: at,
        evidence_ref: "test:" <> action.source_event_key,
        evidence: action.evidence
      })

    saved = Application.get_env(:regent_points, :test_facts, %{})

    Application.put_env(
      :regent_points,
      :test_facts,
      Map.put(saved, {site, action.source_event_key}, facts)
    )

    %{
      rule_id: action.rule_id,
      source_app: site,
      source_kind: action.source_kind,
      source_event_key: action.source_event_key
    }
  end

  defp points(account, rule_id) do
    Entry
    |> Ash.Query.filter(
      account_id == ^account and program_id == ^Rules.program() and rule_id == ^rule_id
    )
    |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
    |> Enum.map(& &1.points_micro_delta)
  end

  defp events(account, rule_id) do
    Event
    |> Ash.Query.filter(
      account_id == ^account and program_id == ^Rules.program() and rule_id == ^rule_id
    )
    |> Ash.read!(actor: Store.system())
    |> Enum.map(&{&1.source_app, &1.processing_status, &1.reason_code})
  end
end

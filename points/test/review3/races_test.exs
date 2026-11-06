Code.require_file("helpers.exs", __DIR__)

defmodule Review3.RacesTest do
  # Real races: every competitor runs on its own database connection, outside the
  # test sandbox, so each award is its own committed transaction as in production.
  # Run only on a fresh database of its own, outside `mix check`:
  #   MIX_TEST_PARTITION=_races mix test --only races test/review3/races_test.exs
  # The rows these tests commit stay there.
  use ExUnit.Case, async: false
  import Review3.Helpers
  alias Ecto.Adapters.SQL.Sandbox
  alias RegentPoints.{IntakeWorker, Repo}

  @moduletag :races
  @moduletag timeout: 120_000

  setup do
    on_exit(configure("review3-races"))
    :ok
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  # Records the event the way the site's intake job does, but leaves its award
  # job unrun, and answers the event's id.
  defp recorded(rule, account, at, evidence, opts \\ []) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      facts = facts(rule, account, at, evidence, opts)
      Review3.Source.put(facts.source_event_key, facts)

      :ok =
        IntakeWorker.perform(%Oban.Job{
          args: %{
            "rule_id" => rule,
            "source_app" => facts.source_app,
            "source_kind" => facts.source_kind,
            "source_event_key" => facts.source_event_key
          }
        })

      [event] = events(facts.source_event_key)
      {facts.source_event_key, event.id}
    end)
  end

  # Runs every function at the same moment, each on its own connection.
  defp together(funs) do
    parent = self()

    tasks =
      for fun <- funs do
        Task.async(fn ->
          unboxed(fn ->
            send(parent, {:ready, self()})

            receive do
              :go -> :ok
            end

            try do
              fun.()
            rescue
              error -> {:raised, Exception.message(error)}
            catch
              kind, value -> {:raised, inspect({kind, value})}
            end
          end)
        end)
      end

    for _ <- tasks do
      receive do
        {:ready, _pid} -> :ok
      end
    end

    for task <- tasks, do: send(task.pid, :go)
    Task.await_many(tasks, 60_000)
  end

  defp award(event_id), do: RegentPoints.process_event(event_id, actor: system())

  # The two faces of the collision: a unique violation on the payment row's second
  # index, or a Postgres deadlock between the speculative inserts (40P01).
  @collision ~r/point_cap_usage_payment_row_once_index|deadlock_detected/

  # Finding 1 (its own test below holds the fix): awards of one new payment made at
  # the same moment collided on the payment row's second unique index, which is
  # gone. This does what Oban does: an award that failed that way, and only that
  # way, is run once more and must then answer. Returns how many collided.
  defp settle(keyed, results) do
    failed =
      for {{_key, id}, result} <- Enum.zip(keyed, results), not match?({:ok, _}, result) do
        assert inspect(result) =~ @collision, inspect(result)
        assert {:ok, _} = unboxed(fn -> award(id) end)
        id
      end

    length(failed)
  end

  test "one payment reported for twelve accounts at the same moment pays exactly one of them" do
    for _round <- 1..5 do
      {evidence, keyed} =
        unboxed(fn ->
          evidence = payment(40_000_000)
          rules = Stream.cycle(spending())

          keyed =
            for {rule, _n} <- Enum.zip(rules, 1..12) do
              recorded(rule, person(), midnight(), evidence)
            end

          {evidence, keyed}
        end)

      results = together(for {_key, id} <- keyed, do: fn -> award(id) end)
      settle(keyed, results)

      unboxed(fn ->
        points = for {key, _id} <- keyed, do: earned(key)
        assert Enum.sort(points) == List.duplicate(0, 11) ++ [40_000_000]
        assert payment_row(evidence) == {1, 40_000_000}
      end)
    end
  end

  test "one account's payments awarded at the same moment across every rule stop at 100 dollars" do
    for _round <- 1..5 do
      {account, keyed} =
        unboxed(fn ->
          account = person()

          keyed =
            for {rule, _n} <- Enum.zip(Stream.cycle(spending()), 1..12) do
              recorded(rule, account, midnight(), payment(30_000_000))
            end

          {account, keyed}
        end)

      results = together(for {_key, id} <- keyed, do: fn -> award(id) end)
      assert Enum.all?(results, &match?({:ok, _}, &1)), inspect(results)

      unboxed(fn ->
        points = for {key, _id} <- keyed, do: earned(key)
        assert Enum.sum(points) == limit()

        assert Enum.sort(points) ==
                 List.duplicate(0, 8) ++ [10_000_000 | List.duplicate(30_000_000, 3)]

        assert day_row(account, midnight()) == {4, limit()}
        assert total(account) == limit()
      end)
    end
  end

  test "whole reports (intake and award in one go) made at the same moment still pay one payment once and keep the day's limit" do
    for _round <- 1..3 do
      {account, others, evidence} =
        unboxed(fn -> {person(), for(_ <- 1..5, do: person()), payment(70_000_000)} end)

      mine =
        for rule <- spending() do
          key = "r3-" <> hex(16)
          {key, fn -> pay(rule, account, midnight(), 45_000_000, key: key) end}
        end

      shared =
        for {other, rule} <- Enum.zip(others, Stream.cycle(spending())) do
          key = "r3-" <> hex(16)
          {key, fn -> pay(rule, other, midnight(), evidence, key: key) end}
        end

      {keys, funs} = Enum.unzip(mine ++ shared)
      results = together(funs)

      # Here the site's own Oban runs the award at once, so a collision (finding 1)
      # surfaces as a raise out of the report itself; in production the award job
      # fails and Oban runs it again, which this does by hand.
      for result <- results,
          not is_binary(result),
          do: assert(inspect(result) =~ @collision, inspect(result))

      unboxed(fn ->
        for key <- keys, event <- events(key), event.processing_status == :pending do
          assert {:ok, _} = award(event.id)
        end
      end)

      unboxed(fn ->
        assert total(account) == limit()
        assert Enum.sum(for other <- others, do: total(other)) == 70_000_000
        assert payment_row(evidence) == {1, 70_000_000}
      end)
    end
  end

  test "a full take-back racing the right account's report and a replay of itself leaves the payment paid at most once" do
    for round <- 1..8 do
      {evidence, wrong, right, entry_id, right_key, right_event} =
        unboxed(fn ->
          [wrong, right] = [person(), person()]
          evidence = payment(60_000_000)
          wrong_key = pay("keyfleet.key_spend", wrong, midnight(), evidence)

          {right_key, right_event} =
            recorded("patchbay.payment_spend", right, midnight(), evidence)

          {evidence, wrong, right, entry(wrong_key).id, right_key, right_event}
        end)

      take_back = fn ->
        RegentPoints.reverse(entry_id, "wrong-#{round}", 60_000_000, "wrong_account",
          actor: system()
        )
      end

      results = together([take_back, fn -> award(right_event) end, take_back, take_back])
      assert Enum.all?(results, &match?({:ok, _}, &1)), inspect(results)

      unboxed(fn ->
        assert total(wrong) == 0
        right_points = earned(right_key)
        assert right_points in [0, 60_000_000]

        # The row says exactly what the ledger says.
        assert payment_row(evidence) ==
                 if(right_points == 0, do: {0, 0}, else: {1, 60_000_000})

        assert total(right) == right_points
        # The wrong account's day stays used, the take-back was written once.
        assert day_row(wrong, midnight()) == {1, 60_000_000}
        assert length(entries(wrong)) == 2
      end)
    end
  end

  test "two full take-backs under different keys at the same moment: one is written, the payment is freed once" do
    for round <- 1..6 do
      {evidence, account, entry_id} =
        unboxed(fn ->
          account = person()
          evidence = payment(25_000_000)
          key = pay("autolaunch.auction_bid_spend", account, midnight(), evidence)
          {evidence, account, entry(key).id}
        end)

      results =
        together(
          for n <- 1..4 do
            fn ->
              RegentPoints.reverse(entry_id, "k#{round}-#{n}", 25_000_000, "wrong",
                actor: system()
              )
            end
          end
        )

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1, inspect(results)
      assert Enum.count(results, &match?({:error, _}, &1)) == 3, inspect(results)

      unboxed(fn ->
        assert total(account) == 0
        assert payment_row(evidence) == {0, 0}
      end)
    end
  end

  test "partial take-backs of one award at the same moment never add up to more than the award" do
    for round <- 1..6 do
      {evidence, account, entry_id} =
        unboxed(fn ->
          account = person()
          evidence = payment(100_000_000)
          key = pay("keyfleet.key_spend", account, midnight(), evidence)
          {evidence, account, entry(key).id}
        end)

      results =
        together(
          for n <- 1..4 do
            fn ->
              RegentPoints.reverse(entry_id, "p#{round}-#{n}", 60_000_000, "partly",
                actor: system()
              )
            end
          end
        )

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1, inspect(results)

      unboxed(fn ->
        assert total(account) == 40_000_000
        assert payment_row(evidence) == {1, 100_000_000}
      end)
    end
  end

  test "0 corrections of one 0-point award at the same moment: one is written" do
    for round <- 1..6 do
      {evidence, account, entry_id} =
        unboxed(fn ->
          account = person()
          pay("keyfleet.key_spend", account, midnight(), limit())
          evidence = payment(25_000_000)
          key = pay("patchbay.payment_spend", account, midnight(), evidence)
          assert payment_row(evidence) == {1, 0}
          {evidence, account, entry(key).id}
        end)

      results =
        together(
          for n <- 1..4 do
            fn ->
              RegentPoints.reverse(entry_id, "z#{round}-#{n}", 0, "wrong", actor: system())
            end
          end
        )

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1, inspect(results)

      unboxed(fn ->
        assert payment_row(evidence) == {0, 0}
        assert length(entries(account)) == 3
      end)
    end
  end

  test "PROOF finding 1: awards of one new payment made at the same moment for different accounts all answer, one paid and the rest 0-point repeats" do
    rounds = 40

    collided =
      for _round <- 1..rounds do
        {evidence, keyed} =
          unboxed(fn ->
            evidence = payment(20_000_000)

            keyed =
              for {rule, _n} <- Enum.zip(Stream.cycle(spending()), 1..8) do
                recorded(rule, person(), midnight(), evidence)
              end

            {evidence, keyed}
          end)

        results = together(for {_key, id} <- keyed, do: fn -> award(id) end)
        failed = for result <- results, not match?({:ok, _}, result), do: result

        # What the failed award answered: an error naming the payment row's second
        # unique index, where the rule is a 0-point repeat entry.
        for result <- failed do
          assert {:error, error} = result
          assert inspect(error) =~ @collision, inspect(error)
        end

        # The failed awards wrote nothing and their events still wait.
        unboxed(fn ->
          waiting =
            for {key, _id} <- keyed,
                event <- events(key),
                event.processing_status == :pending,
                do: key

          assert length(waiting) == length(failed)
          for key <- waiting, do: assert(entry(key) == nil)
        end)

        # Run again, as Oban does, each one answers and the ledger is right.
        assert settle(keyed, results) == length(failed)

        unboxed(fn ->
          points = for {key, _id} <- keyed, do: earned(key)
          assert Enum.sort(points) == List.duplicate(0, 7) ++ [20_000_000]
          assert payment_row(evidence) == {1, 20_000_000}
        end)

        {length(failed), Enum.count(failed, &(inspect(&1) =~ "deadlock_detected"))}
      end

    {failed, deadlocks} = Enum.unzip(collided)

    IO.puts(
      "\nfinding 1: #{Enum.count(failed, &(&1 > 0))} of #{rounds} rounds had a collision; " <>
        "#{Enum.sum(failed)} of #{rounds * 8} simultaneous awards failed " <>
        "(#{Enum.sum(failed) - Enum.sum(deadlocks)} unique violations on the payment row's second index, " <>
        "#{Enum.sum(deadlocks)} Postgres deadlocks)"
    )

    assert Enum.sum(failed) == 0
  end
end

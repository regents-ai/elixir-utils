defmodule RegentPoints.IntakeTest do
  # What record_event answers in the site's own action, before any check runs. The
  # check it queues waits, as on a site, so a test sees only what was queued.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: RegentPoints.Repo
  alias RegentPoints.{IntakeWorker, Store}

  defmodule Source do
    @moduledoc false
    def verify(_reference), do: {:error, :not_asked_here}
  end

  @rule "social.x"
  @limit String.duplicate("7", 510)
  @over String.duplicate("7", 511)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentPoints.Repo)
    keys = [:program_id, :starts_at, :approved_rules, :adapters]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    Application.put_env(:regent_points, :program_id, "intake-test")
    Application.put_env(:regent_points, :starts_at, DateTime.add(DateTime.utc_now(), -3600))
    Application.put_env(:regent_points, :adapters, %{@rule => Source})
    :ok
  end

  test "a rule that is off answers disabled for any source key and queues nothing" do
    Application.put_env(:regent_points, :approved_rules, [])

    Oban.Testing.with_testing_mode(:manual, fn ->
      for key <- ["x:" <> @limit, "x:" <> @over, ""] do
        assert {:ok, %{status: :disabled}} = record(key)
      end

      refute_enqueued(worker: IntakeWorker)
    end)
  end

  test "a rule that is on queues a source key of 512 bytes and refuses one of 513" do
    Application.put_env(:regent_points, :approved_rules, [@rule])
    assert byte_size("x:" <> @limit) == 512

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, %{status: :queued}} = record("x:" <> @limit)
      assert {:error, _} = record("x:" <> @over)

      assert [%{args: %{"source_event_key" => "x:" <> @limit}}] =
               all_enqueued(worker: IntakeWorker)
    end)
  end

  defp record(key),
    do:
      RegentPoints.record_event(
        %{
          rule_id: @rule,
          source_app: "site-a",
          source_kind: "linked_identity",
          source_event_key: key
        },
        actor: Store.system()
      )
end

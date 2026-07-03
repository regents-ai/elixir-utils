defmodule SiwaKeyring.ReplayStoreTest do
  use ExUnit.Case, async: false

  @table SiwaKeyring.ReplayStore
  @expiry_table Module.concat(SiwaKeyring.ReplayStore, Expiry)
  @cleanup_limit 1_000

  setup do
    original = Application.get_env(:siwa_keyring, :replay_store)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:siwa_keyring, :replay_store)
        value -> Application.put_env(:siwa_keyring, :replay_store, value)
      end
    end)

    :ok
  end

  test "delegates replay consumption to a configured shared store" do
    parent = self()

    Application.put_env(:siwa_keyring, :replay_store, fn request_id, expires_at_ms ->
      send(parent, {:replay_consumed, request_id, expires_at_ms})
      :ok
    end)

    assert :ok = SiwaKeyring.ReplayStore.consume("request-00000001", 1_777_978_831_438)
    assert_receive {:replay_consumed, "request-00000001", 1_777_978_831_438}
  end

  test "accepts a fresh request id once and rejects the exact replay" do
    request_id = unique_request_id()
    expires_at_ms = System.system_time(:millisecond) + 60_000
    track_for_cleanup([{request_id, expires_at_ms}])

    assert :ok = SiwaKeyring.ReplayStore.consume(request_id, expires_at_ms)

    assert {:error, :replayed_request} =
             SiwaKeyring.ReplayStore.consume(request_id, expires_at_ms)
  end

  test "rejects an expired request without recording it" do
    request_id = unique_request_id()
    expires_at_ms = System.system_time(:millisecond) - 1

    assert {:error, :expired_request} =
             SiwaKeyring.ReplayStore.consume(request_id, expires_at_ms)

    assert :ets.lookup(@table, request_id) == []
  end

  test "cleanup drops expired request ids but never evicts still-valid ones" do
    pid = Process.whereis(SiwaKeyring.ReplayStore)
    now_ms = System.system_time(:millisecond)
    stale_expires_at_ms = now_ms - 60_000
    fresh_expires_at_ms = now_ms + 60_000

    stale_ids = for _index <- 1..25, do: unique_request_id()
    fresh_id = unique_request_id()

    track_for_cleanup(
      Enum.map(stale_ids, &{&1, stale_expires_at_ms}) ++ [{fresh_id, fresh_expires_at_ms}]
    )

    :ets.insert(@table, Enum.map(stale_ids, &{&1, stale_expires_at_ms}))
    :ets.insert(@expiry_table, Enum.map(stale_ids, &{{stale_expires_at_ms, &1}, true}))

    assert :ok = SiwaKeyring.ReplayStore.consume(fresh_id, fresh_expires_at_ms)

    run_cleanup_pass(pid)

    assert Enum.all?(stale_ids, &(:ets.lookup(@table, &1) == []))
    assert [{^fresh_id, ^fresh_expires_at_ms}] = :ets.lookup(@table, fresh_id)

    assert {:error, :replayed_request} =
             SiwaKeyring.ReplayStore.consume(fresh_id, fresh_expires_at_ms)
  end

  test "cleanup work per pass is bounded and valid keys survive every pass" do
    pid = Process.whereis(SiwaKeyring.ReplayStore)
    now_ms = System.system_time(:millisecond)
    stale_expires_at_ms = now_ms - 60_000
    fresh_expires_at_ms = now_ms + 60_000
    stale_count = @cleanup_limit + 200

    stale_ids = for _index <- 1..stale_count, do: unique_request_id()
    fresh_id = unique_request_id()

    track_for_cleanup(
      Enum.map(stale_ids, &{&1, stale_expires_at_ms}) ++ [{fresh_id, fresh_expires_at_ms}]
    )

    :ets.insert(@table, Enum.map(stale_ids, &{&1, stale_expires_at_ms}))
    :ets.insert(@expiry_table, Enum.map(stale_ids, &{{stale_expires_at_ms, &1}, true}))

    assert :ok = SiwaKeyring.ReplayStore.consume(fresh_id, fresh_expires_at_ms)

    run_cleanup_pass(pid)

    remaining_after_one_pass = Enum.count(stale_ids, &(:ets.lookup(@table, &1) != []))
    assert remaining_after_one_pass >= stale_count - @cleanup_limit
    assert [{^fresh_id, ^fresh_expires_at_ms}] = :ets.lookup(@table, fresh_id)

    Enum.each(1..10, fn _pass -> run_cleanup_pass(pid) end)

    assert Enum.all?(stale_ids, &(:ets.lookup(@table, &1) == []))
    assert [{^fresh_id, ^fresh_expires_at_ms}] = :ets.lookup(@table, fresh_id)

    assert {:error, :replayed_request} =
             SiwaKeyring.ReplayStore.consume(fresh_id, fresh_expires_at_ms)
  end

  test "exactly one of many simultaneous consumes of the same request id is accepted" do
    request_id = unique_request_id()
    expires_at_ms = System.system_time(:millisecond) + 60_000
    attempt_count = 50
    parent = self()
    track_for_cleanup([{request_id, expires_at_ms}])

    pids =
      for _index <- 1..attempt_count do
        spawn_link(fn ->
          receive do
            :go ->
              send(parent, {:result, SiwaKeyring.ReplayStore.consume(request_id, expires_at_ms)})
          end
        end)
      end

    Enum.each(pids, &send(&1, :go))

    results =
      for _index <- 1..attempt_count do
        receive do
          {:result, result} -> result
        after
          5_000 -> flunk("timed out waiting for a concurrent consume result")
        end
      end

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :replayed_request})) == attempt_count - 1
  end

  defp unique_request_id do
    "request-#{System.unique_integer([:positive, :monotonic])}-#{:erlang.unique_integer([:positive])}"
  end

  defp track_for_cleanup(entries) do
    on_exit(fn ->
      Enum.each(entries, fn {request_id, expires_at_ms} ->
        :ets.delete(@table, request_id)
        :ets.delete(@expiry_table, {expires_at_ms, request_id})
      end)
    end)
  end

  # Sends one :cleanup message and synchronizes on the store's mailbox: the
  # :sys.get_state/1 reply proves the earlier :cleanup message was processed.
  defp run_cleanup_pass(pid) do
    send(pid, :cleanup)
    :sys.get_state(pid)
    :ok
  end
end

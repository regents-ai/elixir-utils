defmodule Siwa.Nonce.TokenReplayStore do
  use GenServer

  @table __MODULE__
  @expiry_table Module.concat(__MODULE__, Expiry)
  @cleanup_interval_ms :timer.minutes(1)
  @cleanup_limit 1_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def consume(key, expires_at_ms) do
    case :ets.insert_new(@table, {key, expires_at_ms}) do
      true ->
        :ets.insert(@expiry_table, {{expires_at_ms, key}, true})
        :ok

      false ->
        {:error, :nonce_already_used}
    end
  end

  @impl true
  def init(opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    :ets.new(@expiry_table, [:named_table, :public, :ordered_set])

    state = %{
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @cleanup_interval_ms),
      cleanup_limit: Keyword.get(opts, :cleanup_limit, @cleanup_limit),
      timer_ref: nil
    }

    {:ok, schedule_cleanup(state)}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now_ms = System.system_time(:millisecond)

    cleanup_expired(now_ms, state.cleanup_limit)

    {:noreply, schedule_cleanup(%{state | timer_ref: nil})}
  end

  defp cleanup_expired(now_ms, limit) do
    cleanup_expired(:ets.first(@expiry_table), now_ms, limit, 0)
  end

  defp cleanup_expired(_entry, _now_ms, limit, count) when count >= limit, do: :ok
  defp cleanup_expired(:"$end_of_table", _now_ms, _limit, _count), do: :ok

  defp cleanup_expired({expires_at_ms, key} = entry, now_ms, limit, count)
       when expires_at_ms <= now_ms do
    next_entry = :ets.next(@expiry_table, entry)

    :ets.delete(@expiry_table, entry)
    delete_key_if_expired(key, now_ms)

    cleanup_expired(next_entry, now_ms, limit, count + 1)
  end

  defp cleanup_expired(_entry, _now_ms, _limit, _count), do: :ok

  defp delete_key_if_expired(key, now_ms) do
    case :ets.lookup(@table, key) do
      [{^key, expires_at_ms}] when expires_at_ms <= now_ms -> :ets.delete(@table, key)
      _entry -> :ok
    end
  end

  defp schedule_cleanup(state) do
    %{state | timer_ref: Process.send_after(self(), :cleanup, state.cleanup_interval_ms)}
  end
end

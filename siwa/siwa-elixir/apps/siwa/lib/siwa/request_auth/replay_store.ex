defmodule Siwa.RequestAuth.ReplayStore do
  @moduledoc """
  This node's record of the signed requests it has served, each kept until the
  request could no longer be accepted (see `Siwa.RequestAuth`). Callers write
  straight to the table; this process only owns it and clears ended entries once
  a minute.

  The record is in memory, so it starts empty after a restart. A site uses it
  only for requests that read (`Siwa.AgentAuthPlug`'s `read_only: true`); every
  other request is recorded by the sign-in server, which keeps it on disk.
  """

  use GenServer

  @doc "Atomically refuse expired or previously consumed keys. Never extend the signed expiry."
  @callback consume(binary(), pos_integer()) :: :ok | {:error, term()}

  @sweep_ms 60_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def consume(key, expires_at_unix) do
    cond do
      expires_at_unix <= System.system_time(:second) -> {:error, :request_expired}
      :ets.insert_new(__MODULE__, {key, expires_at_unix}) -> :ok
      true -> {:error, :replayed_request}
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(__MODULE__, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:second)
    :ets.select_delete(__MODULE__, [{{:_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_ms)
end

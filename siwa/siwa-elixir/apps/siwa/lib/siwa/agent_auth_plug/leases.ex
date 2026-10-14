defmodule Siwa.AgentAuthPlug.Leases do
  @moduledoc """
  The leases this node holds: for each site audience and receipt, what the
  sign-in server answered when it last verified a request under that receipt,
  and until when the site may check requests under it itself
  (`Siwa.RequestAuth.verify_leased_request/3`).

  A lease is kept by the hash of the receipt's exact bytes and lasts until the
  `leaseExpiresAt` the sign-in server gave, never past the receipt's own expiry.
  Callers read and write the table directly; this process only owns it and
  clears ended leases once a minute. The table is in memory, so a restart starts
  with none and each agent's next request goes to the sign-in server.
  """

  use GenServer

  @sweep_ms 60_000

  @type lease :: %{
          receipt: String.t(),
          claims: %{String.t() => term()},
          until_ms: pos_integer(),
          data: map()
        }

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The lease held for `receipt` at `audience`, unless it has ended by `now_ms`."
  @spec fetch(String.t(), String.t(), integer()) :: {:ok, lease()} | :none
  def fetch(audience, receipt, now_ms) when is_binary(receipt) do
    case :ets.lookup(__MODULE__, key(audience, receipt)) do
      [{_key, %{until_ms: until_ms} = lease}] when now_ms < until_ms -> {:ok, lease}
      _none -> :none
    end
  end

  def fetch(_audience, _receipt, _now_ms), do: :none

  @doc "Keeps `lease` for its receipt at `audience`, replacing any earlier one."
  @spec keep(String.t(), lease()) :: :ok
  def keep(audience, %{receipt: receipt} = lease) do
    :ets.insert(__MODULE__, {key(audience, receipt), lease})
    :ok
  end

  defp key(audience, receipt), do: {audience, :crypto.hash(:sha256, receipt)}

  @impl true
  def init(_opts) do
    :ets.new(__MODULE__, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    now_ms = System.system_time(:millisecond)

    :ets.select_delete(__MODULE__, [
      {{:_, %{until_ms: :"$1"}}, [{:"=<", :"$1", now_ms}], [true]}
    ])

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_ms)
end

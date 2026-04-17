defmodule Siwa.RequestAuth.ReplayStore do
  use GenServer

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def consume(key, ttl_ms) do
    GenServer.call(__MODULE__, {:consume, key, ttl_ms})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:consume, key, ttl_ms}, _from, state) do
    now = System.system_time(:millisecond)
    state = Map.reject(state, fn {_k, exp} -> exp <= now end)

    case Map.has_key?(state, key) do
      true -> {:reply, {:error, :replayed_request}, state}
      false -> {:reply, :ok, Map.put(state, key, now + ttl_ms)}
    end
  end
end

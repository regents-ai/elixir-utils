defmodule Siwa.RequestAuth.ReplayStore do
  use GenServer

  @doc "Atomically refuse expired or previously consumed keys. Never extend the signed expiry."
  @callback consume(binary(), pos_integer()) :: :ok | {:error, term()}

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def consume(key, expires_at_unix) do
    GenServer.call(__MODULE__, {:consume, key, expires_at_unix})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:consume, key, expires_at_unix}, _from, state) do
    now = System.system_time(:second)
    state = Map.reject(state, fn {_k, exp} -> exp <= now end)

    cond do
      expires_at_unix <= now -> {:reply, {:error, :request_expired}, state}
      Map.has_key?(state, key) -> {:reply, {:error, :replayed_request}, state}
      true -> {:reply, :ok, Map.put(state, key, expires_at_unix)}
    end
  end
end

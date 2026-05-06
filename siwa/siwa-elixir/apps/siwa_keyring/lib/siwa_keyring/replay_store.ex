defmodule SiwaKeyring.ReplayStore do
  use GenServer

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def consume(request_id, expires_at_ms) do
    case configured_store() do
      nil -> GenServer.call(__MODULE__, {:consume, request_id, expires_at_ms})
      {module, function} -> apply(module, function, [request_id, expires_at_ms])
      module when is_atom(module) -> module.consume(request_id, expires_at_ms)
      fun when is_function(fun, 2) -> fun.(request_id, expires_at_ms)
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:consume, request_id, expires_at_ms}, _from, state) do
    now_ms = System.system_time(:millisecond)
    state = Map.reject(state, fn {_request_id, expires_at} -> expires_at <= now_ms end)

    cond do
      expires_at_ms <= now_ms ->
        {:reply, {:error, :expired_request}, state}

      Map.has_key?(state, request_id) ->
        {:reply, {:error, :replayed_request}, state}

      true ->
        {:reply, :ok, Map.put(state, request_id, expires_at_ms)}
    end
  end

  defp configured_store do
    Application.get_env(:siwa_keyring, :replay_store)
  end
end

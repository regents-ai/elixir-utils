defmodule Siwa.Nonce.TokenReplayStore do
  use GenServer

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def consume(key, expires_at_ms) do
    GenServer.call(__MODULE__, {:consume, key, expires_at_ms})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:consume, key, expires_at_ms}, _from, state) do
    now_ms = System.system_time(:millisecond)

    state =
      Map.reject(state, fn {_stored_key, stored_expires_at_ms} ->
        stored_expires_at_ms <= now_ms
      end)

    case Map.has_key?(state, key) do
      true ->
        {:reply, {:error, :nonce_already_used}, state}

      false ->
        {:reply, :ok, Map.put(state, key, expires_at_ms)}
    end
  end
end

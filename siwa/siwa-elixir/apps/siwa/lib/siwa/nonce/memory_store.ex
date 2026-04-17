defmodule Siwa.Nonce.MemoryStore do
  use GenServer
  @behaviour Siwa.NonceStore

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @impl true
  def put(key, nonce, metadata), do: GenServer.call(__MODULE__, {:put, key, nonce, metadata})

  @impl true
  def consume(key, nonce), do: GenServer.call(__MODULE__, {:consume, key, nonce})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:put, key, nonce, metadata}, _from, state) do
    entry = Map.put(metadata, :nonce, nonce)
    {:reply, :ok, Map.put(state, {key, nonce}, entry)}
  end

  def handle_call({:consume, key, nonce}, _from, state) do
    case Map.pop(state, {key, nonce}) do
      {nil, state} -> {:reply, {:error, :unknown_nonce}, state}
      {entry, state} -> {:reply, {:ok, entry}, state}
    end
  end
end

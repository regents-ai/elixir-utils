defmodule XmtpElixirSdk.Internal.Registry do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @spec reset!(atom()) :: :ok
  def reset!(name), do: GenServer.call(name, :reset)

  @spec subscribe(atom(), term(), pid()) :: :ok
  def subscribe(name, topic, subscriber), do: GenServer.call(name, {:subscribe, topic, subscriber})

  @spec unsubscribe(atom(), term(), pid()) :: :ok
  def unsubscribe(name, topic, subscriber),
    do: GenServer.call(name, {:unsubscribe, topic, subscriber})

  @spec emit(atom(), term(), struct()) :: :ok
  def emit(name, topic, event), do: GenServer.cast(name, {:emit, topic, event})

  @impl true
  def init(_) do
    {:ok, %{topics: %{}, monitors: %{}}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    Enum.each(state.monitors, fn {_pid, ref} -> Process.demonitor(ref, [:flush]) end)
    {:reply, :ok, %{topics: %{}, monitors: %{}}}
  end

  def handle_call({:subscribe, topic, subscriber}, _from, state) do
    state = ensure_monitor(state, subscriber)
    subscribers = Map.get(state.topics, topic, MapSet.new()) |> MapSet.put(subscriber)
    {:reply, :ok, %{state | topics: Map.put(state.topics, topic, subscribers)}}
  end

  def handle_call({:unsubscribe, topic, subscriber}, _from, state) do
    subscribers = Map.get(state.topics, topic, MapSet.new()) |> MapSet.delete(subscriber)
    topics = if MapSet.size(subscribers) == 0, do: Map.delete(state.topics, topic), else: Map.put(state.topics, topic, subscribers)
    state = maybe_drop_monitor(%{state | topics: topics}, subscriber)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:emit, topic, event}, state) do
    state.topics
    |> Map.get(topic, MapSet.new())
    |> Enum.each(fn subscriber -> send(subscriber, {:xmtp, topic, event}) end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, subscriber, _reason}, state) do
    if Map.get(state.monitors, subscriber) == ref do
      topics =
        Enum.reduce(state.topics, %{}, fn {topic, subscribers}, acc ->
          remaining = MapSet.delete(subscribers, subscriber)
          if MapSet.size(remaining) == 0, do: acc, else: Map.put(acc, topic, remaining)
        end)

      {:noreply, %{state | topics: topics, monitors: Map.delete(state.monitors, subscriber)}}
    else
      {:noreply, state}
    end
  end

  defp ensure_monitor(state, subscriber) do
    case Map.fetch(state.monitors, subscriber) do
      {:ok, _ref} -> state
      :error -> %{state | monitors: Map.put(state.monitors, subscriber, Process.monitor(subscriber))}
    end
  end

  defp maybe_drop_monitor(state, subscriber) do
    still_subscribed? =
      Enum.any?(state.topics, fn {_topic, subscribers} -> MapSet.member?(subscribers, subscriber) end)

    if still_subscribed? do
      state
    else
      case Map.pop(state.monitors, subscriber) do
        {nil, _} ->
          state

        {ref, monitors} ->
          Process.demonitor(ref, [:flush])
          %{state | monitors: monitors}
      end
    end
  end
end

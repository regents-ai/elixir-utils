defmodule XmtpElixirSdk.BrowserShim.AsyncStream do
  @moduledoc """
  Small async stream primitive for browser-shim boundaries.

  The stream keeps producer and consumer coordination in one process so the
  browser layer can stay thin. Values are delivered in FIFO order, and `done/1`
  drains pending consumers before closing the stream.
  """

  use GenServer

  @type state :: %__MODULE__{
          queue: :queue.queue(term()),
          waiters: [{pid(), reference()}],
          done?: boolean()
        }

  defstruct queue: :queue.new(), waiters: [], done?: false

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, opts)
  end

  @spec push(GenServer.server(), term()) :: :ok
  def push(server, value) do
    GenServer.cast(server, {:push, value})
  end

  @spec done(GenServer.server()) :: :ok
  def done(server) do
    GenServer.cast(server, :done)
  end

  @spec close(GenServer.server()) :: :ok
  def close(server), do: done(server)

  @spec next(GenServer.server(), timeout()) ::
          {:ok, term()} | {:done, :closed} | {:error, :timeout}
  def next(server, timeout \\ 5_000) do
    ref = make_ref()

    case GenServer.call(server, {:request_next, {self(), ref}}, timeout) do
      {:value, reply} ->
        reply

      :waiting when timeout == :infinity ->
        receive do
          {:async_stream_reply, ^ref, reply} -> reply
        end

      :waiting ->
        receive do
          {:async_stream_reply, ^ref, reply} -> reply
        after
          timeout ->
            :ok = GenServer.call(server, {:cancel_next, ref}, timeout)
            {:error, :timeout}
        end
    end
  end

  @spec stream(GenServer.server()) :: Enumerable.t()
  def stream(server) do
    Stream.resource(
      fn -> server end,
      fn pid ->
        case next(pid, :infinity) do
          {:ok, value} -> {[value], pid}
          {:done, :closed} -> {:halt, pid}
          {:error, _reason} -> {:halt, pid}
        end
      end,
      fn _ -> :ok end
    )
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:request_next, {_pid, _ref}}, _from, %{done?: true} = state) do
    {:reply, {:value, {:done, :closed}}, state}
  end

  @impl true
  def handle_call({:request_next, {pid, ref}}, _from, %{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, value}, rest} ->
        {:reply, {:value, {:ok, value}}, %{state | queue: rest}}

      {:empty, _} ->
        {:reply, :waiting, %{state | waiters: state.waiters ++ [{pid, ref}]}}
    end
  end

  @impl true
  def handle_call({:cancel_next, ref}, _from, state) do
    {:reply, :ok,
     %{
       state
       | waiters: Enum.reject(state.waiters, fn {_pid, waiter_ref} -> waiter_ref == ref end)
     }}
  end

  @impl true
  def handle_cast({:push, _value}, %{done?: true} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:push, value}, %{waiters: [{pid, ref} | rest]} = state) do
    send(pid, {:async_stream_reply, ref, {:ok, value}})
    {:noreply, %{state | waiters: rest}}
  end

  @impl true
  def handle_cast({:push, value}, %{queue: queue} = state) do
    {:noreply, %{state | queue: :queue.in(value, queue)}}
  end

  @impl true
  def handle_cast(:done, %{done?: true} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast(:done, state) do
    Enum.each(state.waiters, fn {pid, ref} ->
      send(pid, {:async_stream_reply, ref, {:done, :closed}})
    end)

    {:noreply, %{state | queue: :queue.new(), waiters: [], done?: true}}
  end
end

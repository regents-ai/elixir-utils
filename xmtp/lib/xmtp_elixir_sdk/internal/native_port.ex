defmodule XmtpElixirSdk.Internal.NativePort do
  @moduledoc false

  use GenServer

  require Logger

  alias XmtpElixirSdk.Error

  @default_timeout 30_000
  @initial_backoff_ms 200
  @max_backoff_ms 5_000
  @native_manifest Path.expand("../../../native/xmtp_native/Cargo.toml", __DIR__)
  @debug_executable Path.expand("../../../native/xmtp_native/target/debug/xmtp_native", __DIR__)
  @release_executable Path.expand(
                        "../../../native/xmtp_native/target/release/xmtp_native",
                        __DIR__
                      )
  @native_profile if Code.ensure_loaded?(Mix), do: Mix.env(), else: :prod

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def request(server, op, params \\ %{}, timeout \\ @default_timeout) when is_binary(op) do
    GenServer.call(server, {:request, op, params, timeout}, timeout + 1_000)
  end

  @impl true
  def init(opts) do
    executable = Keyword.get(opts, :executable, configured_executable())

    case File.exists?(executable) do
      true ->
        {:ok,
         %{
           executable: executable,
           port: open_port(executable),
           requests: %{},
           next_id: 0,
           backoff_ms: @initial_backoff_ms
         }}

      false ->
        {:stop,
         {:xmtp_native_missing,
          "build native bridge with `mix native.build` or set XMTP_NATIVE_EXECUTABLE"}}
    end
  end

  @impl true
  def handle_call({:request, _op, _params, _timeout}, _from, %{port: nil} = state) do
    {:reply, {:error, :bridge_down}, state}
  end

  def handle_call({:request, op, params, timeout}, from, state) do
    id = Integer.to_string(state.next_id + 1)
    payload = Jason.encode!(%{id: id, op: op, params: params}) <> "\n"

    try do
      true = Port.command(state.port, payload)
      timer = Process.send_after(self(), {:request_timeout, id}, timeout)

      {:noreply,
       %{
         state
         | next_id: state.next_id + 1,
           requests: Map.put(state.requests, id, {from, timer})
       }}
    rescue
      ArgumentError -> {:reply, {:error, :bridge_down}, state}
    end
  end

  @impl true
  def handle_info({_port, {:data, {:eol, line}}}, state) do
    handle_line(line, state)
  end

  def handle_info({_port, {:data, line}}, state) when is_binary(line) do
    handle_line(String.trim_trailing(line), state)
  end

  def handle_info({_port, {:exit_status, status}}, state) do
    Logger.warning(
      "xmtp native bridge exited with status #{status}; reopening in #{state.backoff_ms}ms"
    )

    Enum.each(state.requests, fn {_id, {from, timer}} ->
      Process.cancel_timer(timer)
      GenServer.reply(from, {:error, :bridge_down})
    end)

    Process.send_after(self(), :reopen_port, state.backoff_ms)

    {:noreply, %{state | port: nil, requests: %{}, backoff_ms: next_backoff(state.backoff_ms)}}
  end

  def handle_info(:reopen_port, %{port: nil} = state) do
    if File.exists?(state.executable) do
      {:noreply, %{state | port: open_port(state.executable)}}
    else
      Process.send_after(self(), :reopen_port, state.backoff_ms)
      {:noreply, %{state | backoff_ms: next_backoff(state.backoff_ms)}}
    end
  end

  def handle_info(:reopen_port, state), do: {:noreply, state}

  def handle_info({:request_timeout, id}, state) do
    case Map.pop(state.requests, id) do
      {{from, _timer}, requests} ->
        GenServer.reply(
          from,
          {:error, Error.internal("native bridge request timed out", %{id: id})}
        )

        {:noreply, %{state | requests: requests}}

      {nil, _requests} ->
        {:noreply, state}
    end
  end

  defp handle_line(line, state) do
    with {:ok, payload} <- Jason.decode(line),
         %{"id" => id, "ok" => ok?} <- payload,
         {{from, timer}, requests} <- Map.pop(state.requests, id) do
      Process.cancel_timer(timer)

      reply =
        if ok? do
          {:ok, Map.get(payload, "result", %{})}
        else
          {:error,
           Error.internal(Map.get(payload, "error", "native bridge request failed"), %{id: id})}
        end

      GenServer.reply(from, reply)
      {:noreply, %{state | requests: requests, backoff_ms: @initial_backoff_ms}}
    else
      {:error, reason} ->
        Logger.warning(
          "xmtp native bridge sent malformed JSON: #{inspect(reason)}; line=#{inspect(line)}"
        )

        {:noreply, state}

      %{} = payload ->
        Logger.warning("xmtp native bridge sent an unexpected payload shape: #{inspect(payload)}")

        {:noreply, state}

      _unmatched_id ->
        {:noreply, state}
    end
  end

  defp open_port(executable) do
    Port.open({:spawn_executable, executable}, [
      :binary,
      :exit_status,
      line: 65_536,
      args: []
    ])
  end

  defp next_backoff(backoff_ms), do: min(backoff_ms * 2, @max_backoff_ms)

  defp configured_executable do
    cond do
      value = System.get_env("XMTP_NATIVE_EXECUTABLE") ->
        value

      @native_profile == :prod ->
        @release_executable

      true ->
        @debug_executable
    end
  end

  def manifest_path, do: @native_manifest
end

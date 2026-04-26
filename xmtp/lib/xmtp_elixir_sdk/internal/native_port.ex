defmodule XmtpElixirSdk.Internal.NativePort do
  @moduledoc false

  use GenServer

  alias XmtpElixirSdk.Error

  @default_timeout 30_000
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
        port =
          Port.open({:spawn_executable, executable}, [
            :binary,
            :exit_status,
            line: 65_536,
            args: []
          ])

        {:ok, %{port: port, requests: %{}, next_id: 0}}

      false ->
        {:stop,
         {:xmtp_native_missing,
          "build native bridge with `mix native.build` or set XMTP_NATIVE_EXECUTABLE"}}
    end
  end

  @impl true
  def handle_call({:request, op, params, timeout}, from, state) do
    id = Integer.to_string(state.next_id + 1)
    payload = Jason.encode!(%{id: id, op: op, params: params}) <> "\n"

    case Port.command(state.port, payload) do
      true ->
        timer = Process.send_after(self(), {:request_timeout, id}, timeout)

        {:noreply,
         %{
           state
           | next_id: state.next_id + 1,
             requests: Map.put(state.requests, id, {from, timer})
         }}

      false ->
        {:reply, {:error, Error.internal("native bridge is not available", %{})}, state}
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
    Enum.each(state.requests, fn {_id, {from, timer}} ->
      Process.cancel_timer(timer)
      GenServer.reply(from, {:error, Error.internal("native bridge exited", %{status: status})})
    end)

    {:stop, {:native_bridge_exited, status}, %{state | requests: %{}}}
  end

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
      {:noreply, %{state | requests: requests}}
    else
      _error -> {:noreply, state}
    end
  end

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

defmodule XmtpElixirSdk.Internal.StatsServer do
  @moduledoc false

  use GenServer

  alias XmtpElixirSdk.Internal.Names
  alias XmtpElixirSdk.Types

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @spec reset!(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom()) :: :ok
  def reset!(runtime), do: GenServer.call(Names.stats_server(runtime), :reset)

  @spec bump_api(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom(), atom()) :: :ok
  def bump_api(runtime, key), do: GenServer.cast(Names.stats_server(runtime), {:bump_api, key})

  @spec bump_identity(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom(), atom()) :: :ok
  def bump_identity(runtime, key),
    do: GenServer.cast(Names.stats_server(runtime), {:bump_identity, key})

  @spec api_statistics(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom()) ::
          {:ok, Types.ApiStats.t()}
  def api_statistics(runtime), do: GenServer.call(Names.stats_server(runtime), :api_statistics)

  @spec api_identity_statistics(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom()) ::
          {:ok, Types.IdentityStats.t()}
  def api_identity_statistics(runtime),
    do: GenServer.call(Names.stats_server(runtime), :api_identity_statistics)

  @spec api_aggregate_statistics(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom()) ::
          {:ok, String.t()}
  def api_aggregate_statistics(runtime),
    do: GenServer.call(Names.stats_server(runtime), :api_aggregate_statistics)

  @spec clear_all_statistics(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom()) :: :ok
  def clear_all_statistics(runtime),
    do: GenServer.call(Names.stats_server(runtime), :clear_all_statistics)

  @impl true
  def init(_) do
    {:ok, %{api: %Types.ApiStats{}, identity: %Types.IdentityStats{}}}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{api: %Types.ApiStats{}, identity: %Types.IdentityStats{}}}
  end

  def handle_call(:api_statistics, _from, state), do: {:reply, {:ok, state.api}, state}
  def handle_call(:api_identity_statistics, _from, state), do: {:reply, {:ok, state.identity}, state}
  def handle_call(:api_aggregate_statistics, _from, state), do: {:reply, {:ok, inspect(state)}, state}

  def handle_call(:clear_all_statistics, _from, _state) do
    {:reply, :ok, %{api: %Types.ApiStats{}, identity: %Types.IdentityStats{}}}
  end

  @impl true
  def handle_cast({:bump_api, key}, state) do
    {:noreply, %{state | api: Map.update(state.api, key, 1, &((&1 || 0) + 1))}}
  end

  def handle_cast({:bump_identity, key}, state) do
    {:noreply, %{state | identity: Map.update(state.identity, key, 1, &((&1 || 0) + 1))}}
  end
end

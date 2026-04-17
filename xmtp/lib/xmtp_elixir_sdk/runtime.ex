defmodule XmtpElixirSdk.Runtime do
  @moduledoc """
  Named supervised XMTP runtime.
  """

  use Supervisor

  alias XmtpElixirSdk.Internal.Names
  alias XmtpElixirSdk.Internal.Registry
  alias XmtpElixirSdk.Internal.{ConversationServer, IdentityServer, StatsServer, SyncServer}

  defstruct [:name]

  @type t :: %__MODULE__{name: atom()}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, name, name: name)
  end

  @spec new(atom()) :: t()
  def new(name) when is_atom(name), do: %__MODULE__{name: name}

  @spec unique_name() :: atom()
  def unique_name do
    :"xmtp_runtime_#{System.unique_integer([:positive])}"
  end

  @spec reset!(t() | atom()) :: :ok
  def reset!(runtime) do
    :ok = IdentityServer.reset!(runtime)
    :ok = ConversationServer.reset!(runtime)
    :ok = SyncServer.reset!(runtime)
    :ok = StatsServer.reset!(runtime)
    :ok = Registry.reset!(Names.registry(runtime))
  end

  @impl true
  def init(name) do
    children = [
      {Registry, name: Names.registry(name)},
      {IdentityServer, name: Names.identity_server(name), runtime: name},
      {ConversationServer, name: Names.conversation_server(name), runtime: name},
      {SyncServer, name: Names.sync_server(name), runtime: name},
      {StatsServer, name: Names.stats_server(name)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

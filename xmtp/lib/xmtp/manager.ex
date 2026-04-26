defmodule Xmtp.Manager do
  @moduledoc false

  use Supervisor

  alias Xmtp.RoomDefinition

  defstruct name: nil, repo: nil, pubsub: nil, rooms: []

  @type t :: %__MODULE__{
          name: module(),
          repo: module(),
          pubsub: module(),
          rooms: [RoomDefinition.t()]
        }

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    repo = Keyword.fetch!(opts, :repo)
    pubsub = Keyword.fetch!(opts, :pubsub)
    rooms_source = Keyword.get(opts, :rooms, [])
    room_definitions = rooms_source |> resolve_rooms() |> Enum.map(&RoomDefinition.new!/1)
    registry_name = registry_name(name)
    supervisor_name = supervisor_name(name)

    :persistent_term.put({__MODULE__, name, :pubsub}, pubsub)
    :persistent_term.put({__MODULE__, name, :rooms}, room_definitions)
    :persistent_term.put({__MODULE__, name, :repo}, repo)
    :persistent_term.put({__MODULE__, name, :rooms_source}, rooms_source)
    :persistent_term.put({__MODULE__, name, :registry}, registry_name)
    :persistent_term.put({__MODULE__, name, :supervisor}, supervisor_name)

    children =
      [
        {Registry, keys: :unique, name: registry_name},
        {DynamicSupervisor, name: supervisor_name, strategy: :one_for_one}
      ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def registry_name(name), do: Module.concat(name, Registry)
  def supervisor_name(name), do: Module.concat(name, DynamicSupervisor)

  def pubsub(name), do: :persistent_term.get({__MODULE__, name, :pubsub})
  def repo(name), do: :persistent_term.get({__MODULE__, name, :repo})
  def rooms_source(name), do: :persistent_term.get({__MODULE__, name, :rooms_source})

  def runtime_name(name, room_key) do
    suffix =
      room_key
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9]+/, "_")
      |> Macro.camelize()

    Module.concat(name, "Runtime#{suffix}")
  end

  def via(name, room_key), do: {:via, Registry, {registry_name(name), to_string(room_key)}}

  def topic(name, room_key), do: "#{inspect(name)}:#{room_key}:refresh"

  def ensure_room_started(name, room_key) do
    room_key = to_string(room_key)

    if room_started?(name, room_key) do
      :ok
    else
      start_room(name, room_key)
    end
  end

  defp resolve_rooms({:mfa, module, function, args}), do: apply(module, function, args)
  defp resolve_rooms(rooms), do: rooms

  def load_room_definition({:mfa, module, function, args}, room_key) do
    module
    |> apply(function, args)
    |> Enum.map(&RoomDefinition.new!/1)
    |> Enum.find(&(&1.key == room_key))
  end

  def cached_room_definition(name, room_key) do
    case rooms_source(name) do
      {:mfa, _module, _function, _args} = source ->
        source
        |> load_room_definition(room_key)
        |> cache_room_definition(name)

      _rooms ->
        :persistent_term.get({__MODULE__, name, :rooms})
        |> Enum.find(&(&1.key == room_key))
    end
  end

  defp loader_for(name, room_key),
    do: {:mfa, __MODULE__, :cached_room_definition, [name, room_key]}

  defp room_started?(name, room_key) do
    name
    |> registry_name()
    |> Registry.lookup(room_key)
    |> Enum.any?()
  end

  defp start_room(name, room_key) do
    with %RoomDefinition{} = definition <- room_definition(name, room_key),
         :ok <- start_runtime(name, room_key),
         :ok <- start_room_server(name, room_key, definition) do
      :ok
    else
      nil -> {:error, :unknown_room}
      {:error, {:already_started, _pid}} -> :ok
      {:error, {:already_present, _child}} -> :ok
      {:error, :already_present} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp room_definition(name, room_key) do
    case rooms_source(name) do
      {:mfa, _module, _function, _args} = source ->
        source
        |> load_room_definition(room_key)
        |> cache_room_definition(name)

      _rooms ->
        :persistent_term.get({__MODULE__, name, :rooms})
        |> Enum.find(&(&1.key == room_key))
    end
  end

  defp cache_room_definition(nil, _name), do: nil

  defp cache_room_definition(%RoomDefinition{} = definition, name) do
    cached_rooms = :persistent_term.get({__MODULE__, name, :rooms})

    updated_rooms =
      [definition | Enum.reject(cached_rooms, &(&1.key == definition.key))]

    :persistent_term.put({__MODULE__, name, :rooms}, updated_rooms)
    definition
  end

  defp start_runtime(name, room_key) do
    DynamicSupervisor.start_child(
      supervisor_name(name),
      {XmtpElixirSdk.Runtime, name: runtime_name(name, room_key)}
    )
    |> normalize_start_result()
  end

  defp start_room_server(name, room_key, definition) do
    DynamicSupervisor.start_child(
      supervisor_name(name),
      {Xmtp.RoomServer,
       manager: name,
       repo: repo(name),
       pubsub: pubsub(name),
       registry: registry_name(name),
       runtime_name: runtime_name(name, room_key),
       definition: definition,
       definition_loader: loader_for(name, room_key)}
    )
    |> normalize_start_result()
  end

  defp normalize_start_result({:ok, _pid}), do: :ok
  defp normalize_start_result({:error, {:already_started, _pid}}), do: :ok
  defp normalize_start_result(other), do: other
end

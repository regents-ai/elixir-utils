defmodule KohakuPlugins.MemoryStorage do
  @moduledoc """
  In-memory storage for tests and local runs.
  """

  use Agent

  @behaviour KohakuPlugins.Storage

  alias KohakuPlugins.Error

  @type t :: pid() | atom()

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    initial = Keyword.get(opts, :initial, %{})

    if name do
      Agent.start_link(fn -> initial end, name: name)
    else
      Agent.start_link(fn -> initial end)
    end
  end

  @impl true
  def get(storage, key) when is_binary(key) do
    {:ok, Agent.get(storage, &Map.get(&1, key))}
  rescue
    error -> {:error, Error.storage("storage read failed", %{reason: inspect(error)})}
  catch
    :exit, reason -> {:error, Error.storage("storage read failed", %{reason: inspect(reason)})}
  end

  @impl true
  def set(storage, key, value) when is_binary(key) and is_binary(value) do
    Agent.update(storage, &Map.put(&1, key, value))
    :ok
  rescue
    error -> {:error, Error.storage("storage write failed", %{reason: inspect(error)})}
  catch
    :exit, reason -> {:error, Error.storage("storage write failed", %{reason: inspect(reason)})}
  end
end

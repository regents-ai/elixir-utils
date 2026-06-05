defmodule RailgunElixir.Runtime do
  @moduledoc """
  Handle for a supervised Railgun native runtime.
  """

  @enforce_keys [:name]
  defstruct [:name]

  @type t :: %__MODULE__{name: atom()}

  @spec new(atom() | t()) :: t()
  def new(%__MODULE__{} = runtime), do: runtime
  def new(name) when is_atom(name), do: %__MODULE__{name: name}

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    RailgunElixir.Internal.NativePort.start_link(Keyword.put(opts, :name, native_port(name)))
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec native_port(atom() | t()) :: atom()
  def native_port(%__MODULE__{name: name}), do: native_port(name)
  def native_port(name) when is_atom(name), do: Module.concat([name, NativePort])
end

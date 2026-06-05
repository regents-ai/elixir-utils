defmodule RailgunElixir.Native do
  @moduledoc false

  alias RailgunElixir.{Runtime, Error}

  @spec request(Runtime.t() | atom(), String.t(), map(), timeout()) ::
          {:ok, map()} | {:error, Error.t()}
  def request(runtime, op, params \\ %{}, timeout \\ 300_000) do
    runtime
    |> Runtime.new()
    |> Runtime.native_port()
    |> RailgunElixir.Internal.NativePort.request(op, stringify_values(params), timeout)
  end

  defp stringify_values(value) when is_map(value) do
    Map.new(value, fn {key, value} -> {to_string(key), stringify_values(value)} end)
  end

  defp stringify_values(value) when is_list(value), do: Enum.map(value, &stringify_values/1)
  defp stringify_values(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_values(value), do: value
end

defmodule KohakuPlugins.Broadcaster do
  @moduledoc """
  Behavior for broadcasting prepared private operations.
  """

  @callback broadcast(term(), term()) :: :ok | {:ok, term()} | {:error, term()}
end

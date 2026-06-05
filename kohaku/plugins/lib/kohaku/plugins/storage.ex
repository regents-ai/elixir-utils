defmodule KohakuPlugins.Storage do
  @moduledoc """
  Storage behavior expected by Kohaku protocol plugins.
  """

  alias KohakuPlugins.Error

  @callback get(term(), String.t()) :: {:ok, String.t() | nil} | {:error, Error.t()}
  @callback set(term(), String.t(), String.t()) :: :ok | {:error, Error.t()}
end

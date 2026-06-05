defmodule KohakuPlugins.Keystore do
  @moduledoc """
  Keystore behavior used by plugins that derive protocol keys.
  """

  alias KohakuPlugins.Error

  @callback derive_at(term(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
end

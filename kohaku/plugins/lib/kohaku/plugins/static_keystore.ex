defmodule KohakuPlugins.StaticKeystore do
  @moduledoc """
  Deterministic keystore for tests and local development.

  Values are derived from the configured seed and requested path. This is not a
  wallet implementation and should not be used as user key storage.
  """

  @behaviour KohakuPlugins.Keystore

  defstruct [:seed]

  alias KohakuPlugins.Error

  @type t :: %__MODULE__{seed: binary()}

  @spec new(binary()) :: t()
  def new(seed \\ :crypto.strong_rand_bytes(32)) when is_binary(seed), do: %__MODULE__{seed: seed}

  @impl true
  def derive_at(%__MODULE__{seed: seed}, path) when is_binary(path) do
    key =
      :crypto.hash(:sha256, seed <> ":" <> path)
      |> Base.encode16(case: :lower)

    {:ok, "0x" <> key}
  end

  def derive_at(_keystore, path),
    do: {:error, Error.keystore("path must be a string", %{value: inspect(path)})}
end

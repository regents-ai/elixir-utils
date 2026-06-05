defmodule RailgunElixir.Signer do
  @moduledoc """
  Railgun signer handle.
  """

  alias RailgunElixir.{Error, Native, Runtime}

  @enforce_keys [:runtime, :id, :address]
  defstruct [:runtime, :id, :address, :chain_id]

  @type t :: %__MODULE__{
          runtime: Runtime.t(),
          id: String.t(),
          address: String.t(),
          chain_id: non_neg_integer() | nil
        }

  @spec spending_key_path(non_neg_integer()) :: String.t()
  def spending_key_path(key_index) when is_integer(key_index) and key_index >= 0 do
    "m/44'/1984'/0'/0'/#{key_index}'"
  end

  @spec viewing_key_path(non_neg_integer()) :: String.t()
  def viewing_key_path(key_index) when is_integer(key_index) and key_index >= 0 do
    "m/420'/1984'/0'/0'/#{key_index}'"
  end

  @spec private_key(Runtime.t() | atom(), String.t(), String.t(), non_neg_integer() | nil) ::
          {:ok, t()} | {:error, Error.t()}
  def private_key(runtime, spending_key, viewing_key, chain_id \\ nil)
      when is_binary(spending_key) and is_binary(viewing_key) do
    runtime = Runtime.new(runtime)

    with {:ok, record} <-
           Native.request(runtime, "signer_private_key", %{
             spending_key: spending_key,
             viewing_key: viewing_key,
             chain_id: chain_id
           }) do
      {:ok, from_native(runtime, record)}
    end
  end

  @spec random(Runtime.t() | atom(), non_neg_integer() | nil) :: {:ok, t()} | {:error, Error.t()}
  def random(runtime, chain_id \\ nil) do
    runtime = Runtime.new(runtime)

    with {:ok, record} <- Native.request(runtime, "signer_random", %{chain_id: chain_id}) do
      {:ok, from_native(runtime, record)}
    end
  end

  @spec from_native(Runtime.t(), map()) :: t()
  def from_native(runtime, record) do
    %__MODULE__{
      runtime: runtime,
      id: record["id"],
      address: record["address"],
      chain_id: record["chain_id"]
    }
  end
end

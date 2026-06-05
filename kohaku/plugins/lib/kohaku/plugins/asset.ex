defmodule KohakuPlugins.Asset do
  @moduledoc """
  Canonical asset identifiers shared by Kohaku Elixir packages.
  """

  alias KohakuPlugins.Error

  @address_regex ~r/^0x[a-fA-F0-9]{40}$/

  @enforce_keys [:type]
  defstruct [:type, :contract, :token_id]

  @type type :: :native | :erc20 | :erc721
  @type t :: %__MODULE__{
          type: type(),
          contract: String.t() | nil,
          token_id: non_neg_integer() | nil
        }

  @spec native() :: t()
  def native, do: %__MODULE__{type: :native}

  @spec erc20(String.t()) :: {:ok, t()} | {:error, Error.t()}
  def erc20(contract) do
    with {:ok, contract} <- normalize_address(contract) do
      {:ok, %__MODULE__{type: :erc20, contract: contract}}
    end
  end

  @spec erc721(String.t(), non_neg_integer()) :: {:ok, t()} | {:error, Error.t()}
  def erc721(contract, token_id) when is_integer(token_id) and token_id >= 0 do
    with {:ok, contract} <- normalize_address(contract) do
      {:ok, %__MODULE__{type: :erc721, contract: contract, token_id: token_id}}
    end
  end

  def erc721(_contract, token_id) do
    {:error,
     Error.invalid_argument("token id must be a non-negative integer", %{value: token_id})}
  end

  @spec to_native_map(t()) :: map()
  def to_native_map(%__MODULE__{type: :native}), do: %{"type" => "native"}

  def to_native_map(%__MODULE__{type: :erc20, contract: contract}),
    do: %{"type" => "erc20", "contract" => contract}

  def to_native_map(%__MODULE__{type: :erc721, contract: contract, token_id: token_id}),
    do: %{"type" => "erc721", "contract" => contract, "token_id" => Integer.to_string(token_id)}

  @spec from_native_map(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_native_map(%{"type" => "native"}), do: {:ok, native()}

  def from_native_map(%{"type" => "erc20", "contract" => contract}), do: erc20(contract)

  def from_native_map(%{"type" => "erc721", "contract" => contract, "token_id" => token_id}) do
    with {parsed, ""} <- Integer.parse(to_string(token_id)) do
      erc721(contract, parsed)
    else
      _error ->
        {:error,
         Error.invalid_argument("token id must be a non-negative integer", %{value: token_id})}
    end
  end

  def from_native_map(value) do
    {:error, Error.invalid_argument("unsupported asset", %{value: inspect(value)})}
  end

  @spec normalize_address(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def normalize_address(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(@address_regex, trimmed) do
      {:ok, String.downcase(trimmed)}
    else
      {:error, Error.invalid_argument("invalid address", %{value: value})}
    end
  end

  def normalize_address(value),
    do: {:error, Error.invalid_argument("invalid address", %{value: inspect(value)})}
end

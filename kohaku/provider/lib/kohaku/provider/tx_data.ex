defmodule KohakuProvider.TxData do
  @moduledoc """
  Ethereum transaction request data.
  """

  alias KohakuProvider.Error

  @enforce_keys [:to, :data, :value]
  defstruct [:to, :data, :value, :from]

  @type t :: %__MODULE__{
          to: String.t(),
          data: String.t(),
          value: non_neg_integer(),
          from: String.t() | nil
        }

  @spec new(String.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, t()} | {:error, Error.t()}
  def new(to, data, value \\ 0, opts \\ []) do
    with {:ok, to} <- KohakuProvider.normalize_address(to),
         {:ok, data} <- normalize_data(data),
         :ok <- validate_value(value),
         {:ok, from} <- normalize_optional_from(Keyword.get(opts, :from)) do
      {:ok, %__MODULE__{to: to, data: data, value: value, from: from}}
    end
  end

  @spec from(t() | map()) :: {:ok, t()} | {:error, Error.t()}
  def from(%__MODULE__{} = tx), do: {:ok, tx}

  def from(%{to: to, data: data, value: value} = tx),
    do: new(to, data, value, from: Map.get(tx, :from))

  def from(%{"to" => to, "data" => data, "value" => value} = tx) do
    with {:ok, value} <- normalize_value(value) do
      new(to, data, value, from: Map.get(tx, "from"))
    end
  end

  def from(value),
    do: {:error, Error.invalid_argument("invalid transaction", %{value: inspect(value)})}

  @spec to_rpc(t()) :: map()
  def to_rpc(%__MODULE__{} = tx) do
    %{
      "to" => tx.to,
      "data" => tx.data,
      "value" => KohakuProvider.integer_to_quantity(tx.value)
    }
    |> maybe_put("from", tx.from)
  end

  defp normalize_data("0x" <> hex = value) do
    if rem(byte_size(hex), 2) == 0 and String.match?(hex, ~r/^[a-fA-F0-9]*$/) do
      {:ok, String.downcase(value)}
    else
      {:error, Error.invalid_argument("invalid transaction data", %{value: value})}
    end
  end

  defp normalize_data(value),
    do: {:error, Error.invalid_argument("invalid transaction data", %{value: inspect(value)})}

  defp validate_value(value) when is_integer(value) and value >= 0, do: :ok

  defp validate_value(value),
    do:
      {:error, Error.invalid_argument("transaction value must be non-negative", %{value: value})}

  defp normalize_value(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp normalize_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _error -> KohakuProvider.quantity_to_integer(value)
    end
  end

  defp normalize_value(value),
    do:
      {:error,
       Error.invalid_argument("transaction value must be non-negative", %{value: inspect(value)})}

  defp normalize_optional_from(nil), do: {:ok, nil}
  defp normalize_optional_from(value), do: KohakuProvider.normalize_address(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

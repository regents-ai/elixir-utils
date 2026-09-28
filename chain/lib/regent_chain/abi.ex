defmodule RegentChain.Abi do
  @moduledoc """
  Contract return data and event fields, read strictly: a value is accepted only
  in the one canonical encoding a contract emits, and anything else is `:error`.

  Types are `{:uint, bits}`, `:address`, `:bool`, `:bytes32`, `:bytes` (also used
  for `string`, whose bytes are kept as they are) and `{:array, type}` of any
  static type, such as `{:array, :address}`. A `{:uint, bits}` refuses any value
  of `bits` bits or more, so a field can be bounded tighter than its Solidity
  type. Addresses come back in the lowercase form `RegentChain.Address` uses.

  The JSON-RPC values around them are read here too: `bytes/1` for `0x` data,
  `quantity/1` for numbers and `hash/1` for block and transaction hashes.
  """

  import Bitwise

  alias RegentChain.Address

  @type type ::
          {:uint, pos_integer()}
          | :address
          | :bool
          | :bytes32
          | :bytes
          | {:array, {:uint, pos_integer()} | :address | :bool | :bytes32}

  @doc "The bytes of a `0x` hex string."
  @spec bytes(term()) :: {:ok, binary()} | :error
  def bytes("0x" <> hex) when rem(byte_size(hex), 2) == 0, do: Base.decode16(hex, case: :mixed)
  def bytes(_value), do: :error

  @doc "A JSON-RPC quantity: `0x` and at least one hex digit, no sign."
  @spec quantity(term()) :: {:ok, non_neg_integer()} | :error
  def quantity("0x" <> hex) do
    if hex =~ ~r/\A[0-9a-fA-F]+\z/, do: {:ok, String.to_integer(hex, 16)}, else: :error
  end

  def quantity(_value), do: :error

  @doc "A 32-byte hash, lowercased."
  @spec hash(term()) :: {:ok, String.t()} | :error
  def hash("0x" <> hex = value) when byte_size(hex) == 64 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, _bytes} -> {:ok, String.downcase(value)}
      :error -> :error
    end
  end

  def hash(_value), do: :error

  @doc "One 32-byte word, such as an indexed topic, as a value of a static `type`."
  @spec word(binary(), type()) :: {:ok, term()} | :error
  def word(<<value::256>>, {:uint, bits}) when value < 1 <<< bits, do: {:ok, value}

  def word(<<0::96, address::binary-size(20)>>, :address), do: {:ok, Address.encode(address)}

  def word(<<0::256>>, :bool), do: {:ok, false}
  def word(<<1::256>>, :bool), do: {:ok, true}

  def word(<<word::binary-size(32)>>, :bytes32),
    do: {:ok, "0x" <> Base.encode16(word, case: :lower)}

  def word(_word, _type), do: :error

  @doc """
  A call's return data, or an event's data, as the values of `types`, in order.
  The data must be exactly the canonical encoding: each dynamic value placed
  right after the one before it, zero padding, and nothing left over.
  """
  @spec decode(binary(), [type()]) :: {:ok, list()} | :error
  def decode(data, types) when is_binary(data) and is_list(types) do
    decode(types, data, 0, 32 * length(types), [])
  end

  defp decode([], data, _at, tail_end, values) when byte_size(data) == tail_end,
    do: {:ok, Enum.reverse(values)}

  defp decode([], _data, _at, _tail_end, _values), do: :error

  defp decode([type | types], data, at, tail_end, values) do
    with {:ok, word} <- slice(data, at, 32),
         {:ok, value, tail_end} <- value(type, word, data, tail_end) do
      decode(types, data, at + 32, tail_end, [value | values])
    end
  end

  defp value(:bytes, word, data, tail_end), do: dynamic(:bytes, word, data, tail_end)

  defp value({:array, _type} = type, word, data, tail_end),
    do: dynamic(type, word, data, tail_end)

  defp value(type, word, _data, tail_end) do
    with {:ok, value} <- word(word, type), do: {:ok, value, tail_end}
  end

  # A dynamic value's head is the offset of its tail, which must be where the
  # previous tail ended.
  defp dynamic(type, word, data, tail_end) do
    with {:ok, ^tail_end} <- word(word, {:uint, 256}),
         {:ok, length_word} <- slice(data, tail_end, 32),
         {:ok, length} <- word(length_word, {:uint, 256}),
         {:ok, value, size} <- tail(type, data, tail_end + 32, length) do
      {:ok, value, tail_end + 32 + size}
    else
      _malformed -> :error
    end
  end

  defp tail(:bytes, data, at, length) do
    padded = 32 * div(length + 31, 32)

    with {:ok, body} <- slice(data, at, padded),
         <<value::binary-size(length), padding::binary>> <- body,
         true <- padding == <<0::size(8 * (padded - length))>> do
      {:ok, value, padded}
    else
      _malformed -> :error
    end
  end

  defp tail({:array, type}, data, at, length) do
    with {:ok, body} <- slice(data, at, 32 * length),
         {:ok, values} <- words(body, type, []) do
      {:ok, values, 32 * length}
    end
  end

  defp words(<<>>, _type, values), do: {:ok, Enum.reverse(values)}

  defp words(<<word::binary-size(32), rest::binary>>, type, values) do
    with {:ok, value} <- word(word, type), do: words(rest, type, [value | values])
  end

  defp slice(data, at, size) when at + size <= byte_size(data),
    do: {:ok, binary_part(data, at, size)}

  defp slice(_data, _at, _size), do: :error
end

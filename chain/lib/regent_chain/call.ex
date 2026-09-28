defmodule RegentChain.Call do
  @moduledoc """
  Calldata for one contract function, from its exact signature.

      RegentChain.Call.encode("approve(address,uint256)", [spender, 1_000_000])
      #=> "0x095ea7b3…"

  Addresses are `0x` strings, checked by `RegentChain.Address.argument/1`, so the
  zero address can be passed where a contract reads it as "none"; `bytes` and
  `bytesN` are `0x` hex strings; integers, booleans and strings are themselves;
  a tuple is an Elixir tuple and an array a list. Anything else raises
  `ArgumentError`, so a step that cannot be built never reaches a page.
  """

  alias RegentChain.Address

  @doc "The lowercase `0x` calldata for `signature` called with `arguments`."
  @spec encode(String.t(), list()) :: String.t()
  def encode(signature, arguments) when is_binary(signature) and is_list(arguments) do
    selector = ABI.FunctionSelector.decode(signature)

    if length(selector.types) != length(arguments) do
      raise ArgumentError, "#{signature} takes #{length(selector.types)} arguments"
    end

    values =
      selector.types
      |> Enum.zip(arguments)
      |> Enum.map(fn {type, value} -> value(type, value) end)

    "0x" <> Base.encode16(ABI.encode(selector, values), case: :lower)
  end

  @doc "The four-byte selector of `signature`, as `0x` hex."
  @spec selector(String.t()) :: String.t()
  def selector(signature) do
    <<selector::binary-size(4), _rest::binary>> = ExKeccak.hash_256(signature)
    "0x" <> Base.encode16(selector, case: :lower)
  end

  defp value(:address, value) do
    case Address.argument(value) do
      {:ok, decoded} -> decoded
      :error -> raise ArgumentError, "not an address: #{inspect(value)}"
    end
  end

  defp value(:bytes, value), do: hex!(value)

  defp value({:bytes, size}, value) do
    case hex!(value) do
      bytes when byte_size(bytes) == size -> bytes
      _other -> raise ArgumentError, "not #{size} bytes: #{inspect(value)}"
    end
  end

  defp value({:tuple, types}, value) when is_tuple(value) and tuple_size(value) == length(types),
    do:
      types
      |> Enum.zip(Tuple.to_list(value))
      |> Enum.map(fn {type, item} -> value(type, item) end)
      |> List.to_tuple()

  defp value({:array, type}, values) when is_list(values), do: Enum.map(values, &value(type, &1))

  defp value({:array, type, size}, values) when is_list(values) and length(values) == size,
    do: Enum.map(values, &value(type, &1))

  defp value({:uint, _bits}, value) when is_integer(value) and value >= 0, do: value
  defp value({:int, _bits}, value) when is_integer(value), do: value
  defp value(:bool, value) when is_boolean(value), do: value
  defp value(:string, value) when is_binary(value), do: value

  defp value(type, value), do: raise(ArgumentError, "#{inspect(value)} is not a #{inspect(type)}")

  defp hex!("0x" <> hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> bytes
      :error -> raise ArgumentError, "not hex: 0x#{hex}"
    end
  end

  defp hex!(value), do: raise(ArgumentError, "not hex: #{inspect(value)}")
end

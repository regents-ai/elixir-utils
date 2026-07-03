defmodule AgentWorld.Internal.ABI do
  @moduledoc false

  alias AgentWorld.Error

  @selector_overrides %{
    "isValidSignature(bytes32,bytes)" => "0x1626ba7e"
  }

  @spec selector(String.t()) :: String.t()
  def selector(signature) when is_binary(signature) do
    case Map.fetch(@selector_overrides, signature) do
      {:ok, selector} ->
        selector

      :error ->
        "0x" <>
          (signature
           |> KeccakEx.hash_256()
           |> binary_part(0, 4)
           |> Base.encode16(case: :lower))
    end
  end

  @spec encode_call(String.t(), list()) :: {:ok, String.t()} | {:error, Error.t()}
  def encode_call(signature, args) when is_binary(signature) and is_list(args) do
    with {:ok, encoded_args} <- encode_args(args) do
      {:ok, selector(signature) <> encoded_args}
    end
  end

  @spec decode_uint256(String.t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def decode_uint256("0x" <> payload) when byte_size(payload) == 64 do
    {:ok, String.to_integer(payload, 16)}
  rescue
    _ -> {:error, Error.new({:invalid_rpc_result, payload})}
  end

  def decode_uint256(result), do: {:error, Error.new({:invalid_rpc_result, result})}

  @spec uint256_word(non_neg_integer()) :: String.t()
  def uint256_word(value) when is_integer(value) and value >= 0 do
    value |> Integer.to_string(16) |> String.pad_leading(64, "0")
  end

  @spec address_word(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def address_word("0x" <> rest) when byte_size(rest) == 40 do
    {:ok, String.pad_leading(String.downcase(rest), 64, "0")}
  end

  def address_word(value), do: {:error, Error.new({:invalid_address, inspect(value)})}

  @spec bytes32_word(binary()) :: {:ok, String.t()} | {:error, Error.t()}
  def bytes32_word(value) when is_binary(value) and byte_size(value) == 32 do
    {:ok, Base.encode16(value, case: :lower)}
  end

  def bytes32_word(value), do: {:error, Error.new({:abi_error, {:expected_bytes32, value}})}

  @spec string_tail(String.t()) :: String.t()
  def string_tail(value) when is_binary(value), do: bytes_tail(:erlang.iolist_to_binary(value))

  @spec bytes_tail(binary()) :: String.t()
  def bytes_tail(value) when is_binary(value) do
    hex = Base.encode16(value, case: :lower)

    uint256_word(byte_size(value)) <>
      hex <>
      String.duplicate("0", rem(64 - rem(byte_size(hex), 64), 64))
  end

  defp encode_args(args) do
    case Enum.reduce_while(args, {:ok, {"", "", length(args)}}, &encode_arg/2) do
      {:ok, {head, tail, _dynamic_words}} -> {:ok, head <> tail}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp encode_arg({:uint256, value}, {:ok, {head, tail, dynamic_words}}) do
    {:cont, {:ok, {head <> uint256_word(value), tail, dynamic_words}}}
  end

  defp encode_arg({:bytes32, value}, {:ok, {head, tail, dynamic_words}}) do
    case bytes32_word(value) do
      {:ok, word} -> {:cont, {:ok, {head <> word, tail, dynamic_words}}}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp encode_arg({:address, value}, {:ok, {head, tail, dynamic_words}}) do
    case address_word(value) do
      {:ok, word} -> {:cont, {:ok, {head <> word, tail, dynamic_words}}}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp encode_arg({:string, value}, {:ok, {head, tail, dynamic_words}}) do
    {:cont, {:ok, encode_dynamic_arg(string_tail(value), head, tail, dynamic_words)}}
  end

  defp encode_arg({:bytes, value}, {:ok, {head, tail, dynamic_words}}) when is_binary(value) do
    {:cont, {:ok, encode_dynamic_arg(bytes_tail(value), head, tail, dynamic_words)}}
  end

  defp encode_arg(invalid, {:ok, _acc}) do
    {:halt, {:error, Error.new({:abi_error, {:unsupported_arg, invalid}})}}
  end

  defp encode_dynamic_arg(encoded_tail, head, tail, dynamic_words) do
    offset_bytes = dynamic_words * 32
    new_words = dynamic_words + div(byte_size(encoded_tail), 64)

    {head <> uint256_word(offset_bytes), tail <> encoded_tail, new_words}
  end
end

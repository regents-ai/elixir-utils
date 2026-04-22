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
    {head, tail, _dynamic_words} =
      Enum.reduce(args, {"", "", length(args)}, fn
        {:uint256, value}, {head, tail, dynamic_words} ->
          {head <> uint256_word(value), tail, dynamic_words}

        {:bytes32, value}, {head, tail, dynamic_words} ->
          case bytes32_word(value) do
            {:ok, word} -> {head <> word, tail, dynamic_words}
            {:error, error} -> throw({:error, error})
          end

        {:address, value}, {head, tail, dynamic_words} ->
          case address_word(value) do
            {:ok, word} -> {head <> word, tail, dynamic_words}
            {:error, error} -> throw({:error, error})
          end

        {:string, value}, {head, tail, dynamic_words} ->
          encoded_tail = string_tail(value)
          offset_bytes = dynamic_words * 32
          new_words = dynamic_words + div(byte_size(encoded_tail), 64)
          {head <> uint256_word(offset_bytes), tail <> encoded_tail, new_words}

        {:bytes, value}, {head, tail, dynamic_words} when is_binary(value) ->
          encoded_tail = bytes_tail(value)
          offset_bytes = dynamic_words * 32
          new_words = dynamic_words + div(byte_size(encoded_tail), 64)
          {head <> uint256_word(offset_bytes), tail <> encoded_tail, new_words}

        invalid, _acc ->
          throw({:error, Error.new({:abi_error, {:unsupported_arg, invalid}})})
      end)

    {:ok, head <> tail}
  catch
    {:error, %Error{} = error} -> {:error, error}
  end
end

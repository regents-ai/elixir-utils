defmodule Siwa.EvmPersonalSign do
  @moduledoc """
  EVM personal-sign recovery and verification helpers.
  """

  @personal_prefix "\x19Ethereum Signed Message:\n"

  @type address :: String.t()
  @type error ::
          :invalid_message
          | :invalid_address
          | :invalid_signature
          | :invalid_signature_encoding
          | :invalid_recovery_id
          | :invalid_public_key

  @spec personal_hash(binary()) :: binary()
  def personal_hash(message) when is_binary(message) do
    (@personal_prefix <> Integer.to_string(byte_size(message)) <> message)
    |> KeccakEx.hash_256()
  end

  @spec personal_hash(term()) :: {:error, :invalid_message}
  def personal_hash(_message), do: {:error, :invalid_message}

  @spec recover_personal_address(binary(), binary()) :: {:ok, address()} | {:error, error()}
  def recover_personal_address(message, signature) when is_binary(message) do
    message
    |> personal_hash()
    |> recover_address(signature)
  end

  def recover_personal_address(_message, _signature), do: {:error, :invalid_message}

  @spec verify_personal_signature(binary(), binary(), address()) :: :ok | {:error, error()}
  def verify_personal_signature(message, signature, expected_address)
      when is_binary(expected_address) do
    with {:ok, recovered_address} <- recover_personal_address(message, signature),
         true <- String.downcase(recovered_address) == String.downcase(expected_address) do
      :ok
    else
      false -> {:error, :invalid_signature}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify_personal_signature(_message, _signature, _expected_address),
    do: {:error, :invalid_address}

  @spec recover_address(binary(), binary()) :: {:ok, address()} | {:error, error()}
  def recover_address(<<_::binary-size(32)>> = digest, signature) do
    with {:ok, {compact, recovery_id}} <- compact_signature(signature),
         {:ok, public_key} <- ExSecp256k1.recover_compact(digest, compact, recovery_id),
         {:ok, uncompressed} <- uncompressed_public_key(public_key) do
      {:ok, public_key_to_address(uncompressed)}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_signature}
    end
  end

  def recover_address(_digest, _signature), do: {:error, :invalid_message}

  @spec signature_bytes(binary()) :: {:ok, binary()} | {:error, error()}
  def signature_bytes("0x" <> hex) when byte_size(hex) == 130 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<_::binary-size(65)>> = bytes} -> {:ok, bytes}
      _ -> {:error, :invalid_signature_encoding}
    end
  end

  def signature_bytes(_signature), do: {:error, :invalid_signature_encoding}

  @spec compact_signature(binary()) :: {:ok, {binary(), 0 | 1}} | {:error, error()}
  def compact_signature(signature) do
    with {:ok, bytes} <- signature_bytes(signature),
         <<compact::binary-size(64), v>> <- bytes,
         {:ok, recovery_id} <- recovery_id(v) do
      {:ok, {compact, recovery_id}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_signature}
    end
  end

  @spec public_key_to_address(binary()) :: address()
  def public_key_to_address(<<4, raw::binary-size(64)>>) do
    raw
    |> KeccakEx.hash_256()
    |> binary_part(12, 20)
    |> then(&("0x" <> Base.encode16(&1, case: :lower)))
  end

  defp recovery_id(v) when v in [0, 1], do: {:ok, v}
  defp recovery_id(v) when v in [27, 28], do: {:ok, v - 27}
  defp recovery_id(v) when v >= 35, do: {:ok, rem(v - 35, 2)}
  defp recovery_id(_value), do: {:error, :invalid_recovery_id}

  defp uncompressed_public_key(<<4, _::binary-size(64)>> = key), do: {:ok, key}

  defp uncompressed_public_key(key) do
    case ExSecp256k1.public_key_decompress(key) do
      {:ok, <<4, _::binary-size(64)>> = decompressed} -> {:ok, decompressed}
      _ -> {:error, :invalid_public_key}
    end
  end
end

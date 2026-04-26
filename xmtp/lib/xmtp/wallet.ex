defmodule Xmtp.Wallet do
  @moduledoc false

  @eth_prefix "\x19Ethereum Signed Message:\n"

  @spec normalize_private_key(String.t() | nil) ::
          {:ok, binary()} | {:error, :agent_private_key_missing | :agent_private_key_invalid}
  def normalize_private_key(nil), do: {:error, :agent_private_key_missing}

  def normalize_private_key(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.trim_leading("0x")

    with true <- normalized != "",
         true <- byte_size(normalized) == 64,
         {:ok, key} <- Base.decode16(normalized, case: :mixed) do
      {:ok, key}
    else
      false -> {:error, :agent_private_key_invalid}
      :error -> {:error, :agent_private_key_invalid}
    end
  end

  def normalize_private_key(_value), do: {:error, :agent_private_key_invalid}

  @spec wallet_address(binary()) :: {:ok, String.t()} | {:error, :agent_private_key_invalid}
  def wallet_address(private_key) when is_binary(private_key) do
    with {:ok, public_key} <- ExSecp256k1.create_public_key(private_key),
         <<4, uncompressed::binary-size(64)>> <- public_key do
      hash = KeccakEx.hash_256(uncompressed)
      {:ok, "0x" <> Base.encode16(binary_part(hash, byte_size(hash) - 20, 20), case: :lower)}
    else
      _ -> {:error, :agent_private_key_invalid}
    end
  end

  @spec sign_personal_message(binary(), String.t()) ::
          {:ok, String.t()} | {:error, :agent_private_key_invalid}
  def sign_personal_message(private_key, message)
      when is_binary(private_key) and is_binary(message) do
    digest =
      ("#{@eth_prefix}#{byte_size(message)}" <> message)
      |> KeccakEx.hash_256()

    case ExSecp256k1.sign_compact(digest, private_key) do
      {:ok, {signature, recovery_id}} ->
        recovery_byte = <<recovery_id + 27>>
        {:ok, "0x" <> Base.encode16(signature <> recovery_byte, case: :lower)}

      _ ->
        {:error, :agent_private_key_invalid}
    end
  end
end

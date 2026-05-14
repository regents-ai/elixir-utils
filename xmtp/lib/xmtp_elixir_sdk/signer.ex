defmodule XmtpElixirSdk.Signer do
  @moduledoc """
  Canonical signer payload helpers for signature-request flows.
  """

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types

  @personal_prefix "\x19Ethereum Signed Message:\n"

  defmodule Eoa do
    @moduledoc "Canonical externally owned account signer payload."
    @enforce_keys [:type, :identifier, :signature]
    defstruct [:type, :identifier, :signature]

    @type t :: %__MODULE__{
            type: :eoa,
            identifier: Types.Identifier.t(),
            signature: binary()
          }
  end

  defmodule Scw do
    @moduledoc "Canonical smart-contract wallet signer payload."
    @enforce_keys [:type, :identifier, :signature, :chain_id]
    defstruct [:type, :identifier, :signature, :chain_id, :block_number]

    @type t :: %__MODULE__{
            type: :scw,
            identifier: Types.Identifier.t(),
            signature: binary(),
            chain_id: non_neg_integer(),
            block_number: non_neg_integer() | nil
          }
  end

  @type t :: Eoa.t() | Scw.t()

  @spec eoa(Types.Identifier.t(), binary()) :: {:ok, Eoa.t()} | {:error, Error.t()}
  def eoa(%Types.Identifier{} = identifier, signature) when is_binary(signature) do
    {:ok, %Eoa{type: :eoa, identifier: identifier, signature: signature}}
  end

  def eoa(_identifier, _signature),
    do: {:error, Error.invalid_argument("invalid EOA signer payload", %{})}

  @spec scw(Types.Identifier.t(), binary(), non_neg_integer(), non_neg_integer() | nil) ::
          {:ok, Scw.t()} | {:error, Error.t()}
  def scw(identifier, signature, chain_id, block_number \\ nil)

  def scw(%Types.Identifier{} = identifier, signature, chain_id, block_number)
      when is_binary(signature) and is_integer(chain_id) and chain_id >= 0 and
             (is_nil(block_number) or (is_integer(block_number) and block_number >= 0)) do
    {:ok,
     %Scw{
       type: :scw,
       identifier: identifier,
       signature: signature,
       chain_id: chain_id,
       block_number: block_number
     }}
  end

  def scw(_identifier, _signature, _chain_id, _block_number),
    do: {:error, Error.invalid_argument("invalid SCW signer payload", %{})}

  @spec to_safe_signer(map(), binary()) :: {:ok, t()} | {:error, Error.t()}
  def to_safe_signer(%{type: :eoa, identifier: %Types.Identifier{} = identifier}, signature),
    do: eoa(identifier, signature)

  def to_safe_signer(
        %{type: :scw, identifier: %Types.Identifier{} = identifier, chain_id: chain_id} = signer,
        signature
      ) do
    scw(identifier, signature, chain_id, Map.get(signer, :block_number))
  end

  def to_safe_signer(_signer, _signature),
    do: {:error, Error.invalid_argument("invalid signer shape", %{})}

  @spec verify(t(), binary()) :: :ok | {:error, Error.t()}
  def verify(
        %Eoa{identifier: %Types.Identifier{identifier_kind: :ethereum} = identifier} = signer,
        message
      )
      when is_binary(message) do
    with {:ok, recovered_address} <- recover_personal_address(message, signer.signature),
         true <- String.downcase(recovered_address) == String.downcase(identifier.identifier) do
      :ok
    else
      false -> {:error, Error.invalid_argument("signature does not match signer", %{})}
      {:error, reason} -> {:error, Error.invalid_argument("invalid signature", %{reason: reason})}
    end
  end

  def verify(_signer, _message),
    do: {:error, Error.invalid_argument("invalid signer payload", %{})}

  defp recover_personal_address(message, signature) do
    message
    |> personal_hash()
    |> recover_address(signature)
  end

  defp personal_hash(message) do
    "#{@personal_prefix}#{byte_size(message)}#{message}"
    |> KeccakEx.hash_256()
  end

  defp recover_address(<<_::binary-size(32)>> = digest, "0x" <> signature_hex) do
    with {:ok, signature} <- Base.decode16(signature_hex, case: :mixed),
         <<compact::binary-size(64), v::unsigned-integer-size(8)>> <- signature,
         {:ok, recovery_id} <- recovery_id(v),
         {:ok, public_key} <- ExSecp256k1.recover_compact(digest, compact, recovery_id),
         <<4, uncompressed::binary-size(64)>> <- public_key do
      hash = KeccakEx.hash_256(uncompressed)
      {:ok, "0x" <> Base.encode16(binary_part(hash, byte_size(hash) - 20, 20), case: :lower)}
    else
      :error -> {:error, :invalid_signature_hex}
      _ -> {:error, :invalid_signature}
    end
  end

  defp recover_address(_digest, _signature), do: {:error, :invalid_signature}

  defp recovery_id(value) when value in [0, 1], do: {:ok, value}
  defp recovery_id(value) when value in [27, 28], do: {:ok, value - 27}
  defp recovery_id(value) when value >= 35, do: {:ok, rem(value - 35, 2)}
  defp recovery_id(_value), do: {:error, :invalid_recovery_id}
end

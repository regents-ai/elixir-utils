defmodule XmtpElixirSdk.Signer do
  @moduledoc """
  Canonical signer payload helpers for signature-request flows.
  """

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types

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
end

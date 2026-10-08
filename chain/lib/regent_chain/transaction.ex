defmodule RegentChain.Transaction do
  @moduledoc """
  An EIP-1559 (type 2) transaction signed with a key the app holds, for the few
  sends a server makes itself rather than a person's wallet.

  Pure: the app reads the nonce and fees, keeps the signed bytes and their hash
  before it broadcasts, and broadcasts them itself. Sending the same bytes again
  is the same transaction. The access list is always empty, and every
  transaction calls or pays an address; none creates a contract.
  """

  alias RegentChain.Address

  @type fields :: %{
          chain_id: pos_integer(),
          nonce: non_neg_integer(),
          max_priority_fee_per_gas: non_neg_integer(),
          max_fee_per_gas: non_neg_integer(),
          gas: pos_integer(),
          to: String.t(),
          value: non_neg_integer(),
          data: String.t()
        }

  @type_byte <<2>>

  @doc """
  The signed transaction: `raw`, the `0x` bytes to broadcast, and `hash`, the
  keccak of those bytes, which is the transaction's hash on chain. `to` is an
  address (`RegentChain.Address.decode/1`), `data` is `0x` hex (`"0x"` for a plain
  payment) and `private_key` is 32 raw bytes. Anything else is `:error`.
  """
  @spec sign(fields(), binary()) :: {:ok, %{raw: String.t(), hash: String.t()}} | :error
  def sign(fields, private_key) when is_binary(private_key) and byte_size(private_key) == 32 do
    with {:ok, unsigned} <- unsigned(fields),
         digest = keccak(@type_byte <> ExRLP.encode(unsigned)),
         {:ok, {<<r::binary-size(32), s::binary-size(32)>>, y_parity}} <-
           ExSecp256k1.sign_compact(digest, private_key) do
      raw =
        @type_byte <>
          ExRLP.encode(
            unsigned ++ [y_parity, :binary.decode_unsigned(r), :binary.decode_unsigned(s)]
          )

      {:ok, %{raw: hex(raw), hash: hex(keccak(raw))}}
    else
      _invalid -> :error
    end
  end

  def sign(_fields, _private_key), do: :error

  @doc "The lowercase address of the key's account, the sender of what `sign/2` signs."
  @spec address(binary()) :: {:ok, String.t()} | :error
  def address(private_key) when is_binary(private_key) and byte_size(private_key) == 32 do
    case ExSecp256k1.create_public_key(private_key) do
      {:ok, <<4, public_key::binary-size(64)>>} ->
        {:ok, public_key |> keccak() |> binary_part(12, 20) |> Address.encode()}

      _invalid ->
        :error
    end
  end

  def address(_private_key), do: :error

  defp unsigned(%{
         chain_id: chain_id,
         nonce: nonce,
         max_priority_fee_per_gas: max_priority_fee_per_gas,
         max_fee_per_gas: max_fee_per_gas,
         gas: gas,
         to: to,
         value: value,
         data: "0x" <> data
       })
       when is_integer(chain_id) and chain_id > 0 and is_integer(gas) and gas > 0 do
    quantities = [nonce, max_priority_fee_per_gas, max_fee_per_gas, value]

    with true <- Enum.all?(quantities, &(is_integer(&1) and &1 >= 0)),
         {:ok, to} <- Address.decode(to),
         {:ok, data} <- Base.decode16(data, case: :mixed) do
      {:ok,
       [chain_id, nonce, max_priority_fee_per_gas, max_fee_per_gas, gas, to, value, data, []]}
    else
      _invalid -> :error
    end
  end

  defp unsigned(_fields), do: :error

  defp keccak(bytes), do: ExKeccak.hash_256(bytes)
  defp hex(bytes), do: "0x" <> Base.encode16(bytes, case: :lower)
end

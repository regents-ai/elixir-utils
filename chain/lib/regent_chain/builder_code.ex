defmodule RegentChain.BuilderCode do
  @moduledoc """
  Regent's Base Builder Code, `bc_u09360jo`, which Base uses to credit Regent
  with the transactions its sites' wallet buttons send
  (https://docs.base.org/specifications/builder-codes/overview).

  Every transaction step (`RegentChain.Review.step/4`) ends its calldata with
  `suffix/0`, the ERC-8021 schema 0 suffix: the code in ASCII, its length in one
  byte, the schema id `0x00`, then the 16-byte marker `0x8021` eight times.
  Contracts ignore the extra bytes; Base reads them from the end of the calldata.

  A wallet may add its own code, rewriting the suffix, so a sent transaction is
  matched to its step by `call/1`, the calldata without any schema 0 suffix.
  """

  @code "bc_u09360jo"
  @marker :binary.copy(<<0x80, 0x21>>, 8)
  @hex Base.encode16(@code <> <<byte_size(@code), 0>> <> @marker, case: :lower)
  # Schema 0 and the marker, the suffix's last 18 bytes.
  @tail "00" <> Base.encode16(@marker, case: :lower)

  @doc "The code itself."
  @spec code() :: String.t()
  def code, do: @code

  @doc "The `0x` hex that ends every transaction step's calldata."
  @spec suffix() :: String.t()
  def suffix, do: "0x" <> @hex

  @doc "`data`, lowercase `0x` calldata, with the suffix appended."
  @spec append(String.t()) :: String.t()
  def append("0x" <> _calldata = data), do: data <> @hex

  @doc """
  Lowercase `0x` calldata without its ERC-8021 schema 0 suffix, whatever codes it
  names; calldata with none is returned as it is.
  """
  @spec call(String.t()) :: String.t()
  def call("0x" <> hex = data) do
    with true <- String.ends_with?(hex, @tail),
         rest = binary_part(hex, 0, byte_size(hex) - byte_size(@tail)),
         {:ok, <<length>>} <- Base.decode16(String.slice(rest, -2, 2), case: :lower),
         codes when codes >= 0 <- byte_size(rest) - 2 - 2 * length do
      "0x" <> binary_part(rest, 0, codes)
    else
      _no_suffix -> data
    end
  end
end

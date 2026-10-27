defmodule RegentChain.ReviewTest do
  use ExUnit.Case, async: true

  alias RegentChain.{BuilderCode, Call, Review}

  @zero "0x0000000000000000000000000000000000000000"
  @wallet "0x1111111111111111111111111111111111111111"
  @chain %{chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"}

  test "never names the zero address as the signer or the contract a step calls" do
    clear = Call.encode("setVotingDelegate(address)", [@zero])

    assert %{to: @wallet} = Review.step("clear", @wallet, clear)
    assert_raise ArgumentError, fn -> Review.step("clear", @zero, clear) end
    assert_raise ArgumentError, fn -> Review.new("votes", @zero, @chain, []) end
  end

  test "every transaction ends with Regent's Base Builder Code, read back as ERC-8021 reads it" do
    call = Call.encode("approve(address,uint256)", [@wallet, 1_500_000])
    %{data: "0x" <> hex} = Review.step("approve", @wallet, call)

    # As the code was given (Base Dashboard, 27 Oct 2026).
    assert BuilderCode.suffix() ==
             "0x62635f7530393336306a6f0b0080218021802180218021802180218021"

    assert "0x" <> String.replace_suffix(hex, String.slice(BuilderCode.suffix(), 2..-1//1), "") ==
             call

    # From the end: the marker, schema 0, the codes' length, then the codes.
    bytes = Base.decode16!(hex, case: :lower)
    marker_at = byte_size(bytes) - 16
    assert binary_part(bytes, marker_at, 16) == :binary.copy(<<0x80, 0x21>>, 8)
    assert <<length, 0>> = binary_part(bytes, marker_at - 2, 2)
    codes = binary_part(bytes, marker_at - 2 - length, length)
    assert String.split(codes, ",") == ["bc_u09360jo"]
  end
end

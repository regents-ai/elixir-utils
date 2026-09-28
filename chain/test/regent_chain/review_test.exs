defmodule RegentChain.ReviewTest do
  use ExUnit.Case, async: true

  alias RegentChain.{Call, Review}

  @zero "0x0000000000000000000000000000000000000000"
  @wallet "0x1111111111111111111111111111111111111111"
  @chain %{chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"}

  test "never names the zero address as the signer or the contract a step calls" do
    clear = Call.encode("setVotingDelegate(address)", [@zero])

    assert %{to: @wallet} = Review.step("clear", @wallet, clear)
    assert_raise ArgumentError, fn -> Review.step("clear", @zero, clear) end
    assert_raise ArgumentError, fn -> Review.new("votes", @zero, @chain, []) end
  end
end

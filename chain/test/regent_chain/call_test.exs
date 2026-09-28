defmodule RegentChain.CallTest do
  use ExUnit.Case, async: true

  alias RegentChain.Call

  @zero "0x0000000000000000000000000000000000000000"

  test "encodes the zero address as an argument" do
    # `cast calldata "setVotingDelegate(address)" 0x0000000000000000000000000000000000000000`
    assert Call.encode("setVotingDelegate(address)", [@zero]) ==
             "0xd8939127" <> String.duplicate("0", 64)
  end
end

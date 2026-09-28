defmodule RegentChain.PressesTest do
  use ExUnit.Case, async: true

  alias RegentChain.Presses

  test "a signature the wallet may have made is its own failure reason" do
    assert Presses.failed(%{"step" => "pay", "reason" => "sign_unconfirmed"}) ==
             {:ok, "pay", "sign_unconfirmed"}
  end
end

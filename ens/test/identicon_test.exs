defmodule AgentEns.IdenticonTest do
  use ExUnit.Case, async: true

  alias AgentEns.Identicon

  @wallet "0x1234567890abcdef1234567890abcdef12345678"
  @other_wallet "0x9999999999999999999999999999999999999999"

  test "is deterministic and case-insensitive for the same wallet" do
    upper = "0x" <> String.upcase(String.trim_leading(@wallet, "0x"))

    assert Identicon.svg(@wallet) == Identicon.svg(@wallet)
    assert Identicon.svg(@wallet) == Identicon.svg(upper)
  end

  test "differs across wallets" do
    refute Identicon.svg(@wallet) == Identicon.svg(@other_wallet)
  end

  test "renders a round frame by default and a soft square on request" do
    assert Identicon.svg(@wallet) =~ "border-radius:50%"
    assert Identicon.svg(@wallet, shape: :square) =~ "border-radius:18%"
    refute Identicon.svg(@wallet) =~ ~s(id=")
  end

  test "honors size and stays well-formed" do
    svg = Identicon.svg(@wallet, size: 64)

    assert svg =~ ~s(width="64")
    assert svg =~ ~s(height="64")
    assert String.starts_with?(svg, "<svg ")
    assert String.ends_with?(svg, "</svg>")
  end

  test "invalid wallets still produce a deterministic avatar" do
    assert Identicon.svg(nil) == Identicon.svg(nil)
    assert Identicon.svg("junk") == Identicon.svg("junk")
    refute Identicon.svg("junk") == Identicon.svg(nil)
  end

  test "output contains only generated markup (no raw input echo)" do
    svg = Identicon.svg(~s|<script>alert("x")</script>|)

    refute svg =~ "script"
    refute svg =~ "alert"
  end
end

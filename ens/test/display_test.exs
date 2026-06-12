defmodule AgentEns.DisplayTest do
  use ExUnit.Case, async: true

  doctest AgentEns.Display

  alias AgentEns.Display

  @wallet "0x1234567890abcdef1234567890abcdef12345678"

  test "ens name wins over fallback and wallet" do
    assert Display.name("alice.eth", "Alice", @wallet) == "alice.eth"
  end

  test "fallback wins when ens name is blank" do
    assert Display.name("", "Alice", @wallet) == "Alice"
    assert Display.name(nil, "Alice", @wallet) == "Alice"
    assert Display.name("   ", "Alice", @wallet) == "Alice"
  end

  test "truncated wallet is the last resort before Unknown" do
    assert Display.name(nil, nil, @wallet) == "0x1234…5678"
    assert Display.name(nil, nil, "bogus") == "Unknown"
    assert Display.name(nil, nil, nil) == "Unknown"
  end

  test "names are trimmed" do
    assert Display.name("  alice.eth  ", nil, @wallet) == "alice.eth"
  end

  test "truncate_wallet normalizes case and rejects invalid addresses" do
    assert Display.truncate_wallet("0x1234567890ABCDEF1234567890ABCDEF12345678") == "0x1234…5678"
    assert Display.truncate_wallet("0x123") == nil
    assert Display.truncate_wallet(nil) == nil
  end
end

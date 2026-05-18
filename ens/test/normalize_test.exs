defmodule AgentEns.NormalizeTest do
  use ExUnit.Case, async: true

  alias AgentEns.Normalize

  test "normalizes names with uts46 compatibility processing" do
    assert {:ok, "hello.eth"} = Normalize.normalize("  ℌello.eth. ")
  end

  test "normalizes mixed case and trims surrounding whitespace" do
    assert {:ok, "regent.eth"} = Normalize.normalize("  ReGeNt.ETH ")
  end

  test "normalizes dns imported names without requiring an eth suffix" do
    assert {:ok, "example.com"} = Normalize.normalize(" Example.COM ")
  end
end

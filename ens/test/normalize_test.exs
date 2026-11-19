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

  test "keeps emoji names, which ENS registers" do
    assert {:ok, "😀.eth"} = Normalize.normalize("😀.eth")
  end

  test "refuses ASCII outside letters, digits and hyphens, and empty labels" do
    for name <- ["under_score.eth", "a b.eth", "a$b.eth", "a..b.eth", ".eth", "xn--abc-.eth"] do
      assert {:error, _} = Normalize.normalize(name)
    end
  end

  test "refuses an overlong xn-- label without decoding it" do
    name = "xn--" <> String.duplicate("a", 4_000) <> ".eth"
    {microseconds, result} = :timer.tc(fn -> Normalize.normalize(name) end)

    assert {:error, _} = result
    assert microseconds < 1_000_000
  end
end

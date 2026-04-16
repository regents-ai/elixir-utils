defmodule AgentEns.NormalizeTest do
  use ExUnit.Case, async: true

  alias AgentEns.Normalize

  test "normalizes names with uts46 compatibility processing" do
    assert {:ok, "hello.eth"} = Normalize.normalize("  ℌello.eth. ")
  end
end

defmodule Siwa.NonceTest do
  use ExUnit.Case, async: false

  test "issues and consumes a nonce" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:84532:0xregistry"
             })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:84532:0xregistry",
               nonce: issued.nonce
             })
  end
end

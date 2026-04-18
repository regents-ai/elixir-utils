defmodule Siwa.FixtureReceiptTest do
  use ExUnit.Case, async: true

  test "verifies the frozen JS receipt" do
    fixture = Siwa.TestFixtures.load("receipt")
    data = fixture["case"]

    assert {:ok, payload} =
             Siwa.Receipt.verify(
               data["receipt"],
               secret: data["secret"],
               now: DateTime.from_unix!(data["fixedNowMs"], :millisecond)
             )

    assert payload["address"] == data["verified"]["address"]
    assert payload["agentId"] == data["verified"]["agentId"]
    assert payload["agentRegistry"] == data["verified"]["agentRegistry"]
    assert payload["chainId"] == data["verified"]["chainId"]
    assert payload["verified"] == data["verified"]["verified"]
  end
end

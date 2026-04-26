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

    assert payload["typ"] == data["verified"]["typ"]
    assert payload["sub"] == data["verified"]["sub"]
    assert payload["aud"] == data["verified"]["aud"]
    assert payload["chain_id"] == data["verified"]["chain_id"]
    assert payload["registry_address"] == data["verified"]["registry_address"]
    assert payload["token_id"] == data["verified"]["token_id"]
    assert payload["verified"] == data["verified"]["verified"]
  end
end

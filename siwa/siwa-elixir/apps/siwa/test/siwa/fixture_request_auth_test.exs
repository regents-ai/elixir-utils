defmodule Siwa.FixtureRequestAuthTest do
  use ExUnit.Case, async: false

  test "verifies the frozen HTTP SIWA request envelope" do
    fixture = Siwa.TestFixtures.load("request_auth")
    data = fixture["case"]
    uri = URI.parse(data["request"]["url"])
    path = if uri.query, do: uri.path <> "?" <> uri.query, else: uri.path

    assert {:ok, verified} =
             Siwa.RequestAuth.verify_authenticated_request(
               %{
                 method: data["request"]["method"],
                 path: path,
                 body: data["request"]["body"],
                 headers: data["signedHeaders"]
               },
               secret: "fixture-secret",
               audience: data["receiptPayload"]["aud"],
               now: DateTime.from_unix!(data["fixedNowMs"], :millisecond)
             )

    assert verified.claims["sub"] == data["verified"]["agent"]["wallet_address"]
    assert verified.claims["chain_id"] == data["verified"]["agent"]["chain_id"]
    assert verified.claims["registry_address"] == data["verified"]["agent"]["registry_address"]
    assert verified.claims["token_id"] == data["verified"]["agent"]["token_id"]
  end
end

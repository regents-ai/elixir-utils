defmodule SiwaKeyring.FixtureKeyringTest do
  use ExUnit.Case, async: true

  test "matches the frozen JS keyring auth headers" do
    fixture_path = Path.expand("../../../../fixtures/siwa/keyring.json", __DIR__)
    fixture = fixture_path |> File.read!() |> Jason.decode!()
    data = fixture["case"]

    headers =
      SiwaKeyring.Auth.compute_hmac(
        data["secret"],
        data["method"],
        data["path"],
        data["body"],
        data["headers"]["X-Keyring-Timestamp"]
      )

    assert headers["x-keyring-timestamp"] == data["headers"]["X-Keyring-Timestamp"]
    assert headers["x-keyring-signature"] == data["headers"]["X-Keyring-Signature"]
  end
end

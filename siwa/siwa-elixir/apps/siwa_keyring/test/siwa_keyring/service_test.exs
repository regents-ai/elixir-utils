defmodule SiwaKeyring.ServiceTest do
  use ExUnit.Case, async: false

  test "computes proxy auth headers" do
    headers =
      SiwaKeyring.Auth.compute_hmac("secret", "POST", "/sign-message", "{}",
        request_id: "test-request-id-0001",
        timestamp: "123"
      )

    assert headers["x-keyring-timestamp"] == "123"
    assert headers["x-keyring-request-id"] == "test-request-id-0001"
    assert is_binary(headers["x-keyring-signature"])
  end

  test "returns a missing wallet error when the wallet path is nil" do
    opts = [path: nil, password: "test-password"]

    assert SiwaKeyring.Service.create_wallet(opts) == {:error, :wallet_missing}
    assert SiwaKeyring.Service.get_address(opts) == {:error, :wallet_missing}
    assert SiwaKeyring.Service.sign_message("hello", opts) == {:error, :wallet_missing}
  end

  test "runtime config rejects invalid service settings" do
    old_secret = Application.fetch_env!(:siwa_keyring, :secret)

    try do
      Application.put_env(:siwa_keyring, :secret, "")

      assert_raise ArgumentError, ~r/:secret must be a non-empty string/, fn ->
        SiwaKeyring.Application.runtime_config!()
      end
    after
      Application.put_env(:siwa_keyring, :secret, old_secret)
    end
  end
end

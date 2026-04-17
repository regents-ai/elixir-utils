defmodule SiwaKeyring.ServiceTest do
  use ExUnit.Case, async: false

  test "computes proxy auth headers" do
    headers = SiwaKeyring.Auth.compute_hmac("secret", "POST", "/sign-message", "{}", "123")
    assert headers["x-keyring-timestamp"] == "123"
    assert is_binary(headers["x-keyring-signature"])
  end
end

defmodule SiwaKeyring.ServiceTest do
  use ExUnit.Case, async: false

  test "returns a missing wallet error when the wallet path is nil" do
    opts = [path: nil, password: "test-password"]

    assert SiwaKeyring.Service.create_wallet(opts) == {:error, :wallet_missing}
    assert SiwaKeyring.Service.get_address(opts) == {:error, :wallet_missing}
    assert SiwaKeyring.Service.sign_message("hello", opts) == {:error, :wallet_missing}
  end
end

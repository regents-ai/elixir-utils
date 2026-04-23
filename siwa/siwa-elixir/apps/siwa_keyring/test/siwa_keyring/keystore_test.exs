defmodule SiwaKeyring.KeystoreTest do
  use ExUnit.Case, async: true

  alias SiwaKeyring.Keystore

  @password "test-password"

  test "missing wallet file returns a tagged missing wallet error" do
    path = Path.join(System.tmp_dir!(), "siwa-keyring-#{System.unique_integer([:positive])}.json")
    config = %{path: path, password: @password}

    assert Keystore.has_wallet?(config) == false
    assert Keystore.get_wallet(config) == {:error, :wallet_missing}
    assert Keystore.get_address(config) == {:error, :wallet_missing}
  end

  test "nil wallet path returns a tagged missing wallet error" do
    config = %{path: nil, password: @password}

    assert Keystore.has_wallet?(config) == false
    assert Keystore.get_wallet(config) == {:error, :wallet_missing}
    assert Keystore.get_address(config) == {:error, :wallet_missing}
    assert Keystore.persist_wallet(config, %{}) == {:error, :wallet_missing}
    assert Keystore.create_wallet(config) == {:error, :wallet_missing}
  end
end

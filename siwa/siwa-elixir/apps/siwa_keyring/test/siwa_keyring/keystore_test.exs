defmodule SiwaKeyring.KeystoreTest do
  use ExUnit.Case, async: true

  alias SiwaKeyring.Keystore
  import Bitwise

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

  test "wallet persistence creates an owner-only file and refuses to overwrite it" do
    path = Path.join(System.tmp_dir!(), "siwa-keyring-#{System.unique_integer([:positive])}.json")
    config = %{path: path, password: @password}

    on_exit(fn -> File.rm(path) end)

    wallet = %{
      private_key: "0xabc",
      public_key: "0xdef",
      address: "0x123",
      signer_type: "eoa"
    }

    assert :ok = Keystore.persist_wallet(config, wallet)
    assert {:ok, decoded_wallet} = Keystore.get_wallet(config)
    assert decoded_wallet["private_key"] == wallet.private_key
    assert decoded_wallet["public_key"] == wallet.public_key
    assert decoded_wallet["address"] == wallet.address
    assert decoded_wallet["signer_type"] == wallet.signer_type
    assert {:error, :wallet_already_exists} = Keystore.persist_wallet(config, wallet)

    mode =
      path
      |> File.stat!()
      |> Map.fetch!(:mode)
      |> band(0o777)

    assert mode == 0o600
  end

  test "concurrent wallet creation stores exactly one owner-only wallet file" do
    path = Path.join(System.tmp_dir!(), "siwa-keyring-#{System.unique_integer([:positive])}.json")
    config = %{path: path, password: @password}

    on_exit(fn ->
      File.rm(path)

      path
      |> Path.dirname()
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, Path.basename(path) <> ".tmp-"))
      |> Enum.each(&File.rm(Path.join(Path.dirname(path), &1)))
    end)

    results =
      1..12
      |> Enum.map(fn _ -> Task.async(fn -> Keystore.create_wallet(config) end) end)
      |> Task.await_many(10_000)

    assert Enum.count(results, &match?({:ok, _wallet}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :wallet_already_exists})) == 11
    assert {:ok, wallet_response} = Enum.find(results, &match?({:ok, _wallet}, &1))
    refute Map.has_key?(wallet_response, :private_key)
    assert is_binary(wallet_response.address)
    assert is_binary(wallet_response.public_key)
    assert wallet_response.signer_type == "eoa"

    mode =
      path
      |> File.stat!()
      |> Map.fetch!(:mode)
      |> band(0o777)

    assert mode == 0o600

    assert {:ok, %{"address" => address, "private_key" => private_key}} =
             Keystore.get_wallet(config)

    assert is_binary(address)
    assert is_binary(private_key)
  end

  test "malformed keystore files return a tagged decrypt error" do
    bad_payloads = [
      "not-json",
      Jason.encode!("not-a-map"),
      Jason.encode!(%{}),
      Jason.encode!(%{
        "cipher" => "wrong",
        "salt" => Base.encode64("salt"),
        "iv" => Base.encode64("iv"),
        "ciphertext" => Base.encode64("ciphertext"),
        "tag" => Base.encode64("tag")
      }),
      Jason.encode!(%{
        "cipher" => "aes-256-gcm",
        "salt" => "not-base64",
        "iv" => Base.encode64("iv"),
        "ciphertext" => Base.encode64("ciphertext"),
        "tag" => Base.encode64("tag")
      }),
      Jason.encode!(%{
        "cipher" => "aes-256-gcm",
        "salt" => Base.encode64("salt"),
        "iv" => Base.encode64("short"),
        "ciphertext" => Base.encode64("ciphertext"),
        "tag" => Base.encode64("short")
      })
    ]

    for payload <- bad_payloads do
      assert Keystore.decrypt_wallet(payload, @password) == {:error, :keystore_decrypt_failed}
    end
  end

  test "wrong passwords return a tagged decrypt error" do
    wallet = %{
      private_key: "0xabc",
      public_key: "0xdef",
      address: "0x123",
      signer_type: "eoa"
    }

    encrypted = Keystore.encrypt_wallet(wallet, @password)

    assert Keystore.decrypt_wallet(encrypted, "wrong-password") ==
             {:error, :keystore_decrypt_failed}
  end
end

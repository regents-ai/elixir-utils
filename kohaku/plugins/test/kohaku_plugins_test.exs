defmodule KohakuPluginsTest do
  use ExUnit.Case, async: true

  alias KohakuPlugins.{Asset, AssetAmount, Host, MemoryStorage, StaticKeystore}

  test "builds canonical ERC20 asset amounts" do
    assert {:ok, asset} = Asset.erc20("0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14")
    assert asset.contract == "0xfff9976782d46cc05630d1f6ebab18b2324d6b14"
    assert {:ok, amount} = AssetAmount.new(asset, 5_000)

    assert AssetAmount.to_native_map(amount) == %{
             "asset" => %{
               "contract" => "0xfff9976782d46cc05630d1f6ebab18b2324d6b14",
               "type" => "erc20"
             },
             "amount" => "5000"
           }
  end

  test "rejects invalid asset values" do
    assert {:error, error} = Asset.erc20("bad")
    assert error.kind == :invalid_argument

    assert {:error, error} = AssetAmount.new(Asset.native(), -1)
    assert error.kind == :invalid_argument
  end

  test "host delegates storage and keystore operations" do
    {:ok, storage} = MemoryStorage.start_link()

    host =
      Host.new(
        storage: storage,
        keystore: StaticKeystore.new("seed"),
        provider: %{rpc_url: "http://127.0.0.1:8545"}
      )

    assert :ok = Host.storage_set(host, "railgun:test", "value")
    assert {:ok, "value"} = Host.storage_get(host, "railgun:test")
    assert {:ok, "0x" <> key} = Host.derive_at(host, "m/44'/1984'/0'/0'/0'")
    assert byte_size(key) == 64
  end
end

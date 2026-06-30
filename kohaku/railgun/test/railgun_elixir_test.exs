defmodule RailgunElixirTest do
  use ExUnit.Case, async: false

  alias KohakuPlugins.{Asset, AssetAmount}
  alias RailgunElixir.{DatabaseAdapter, Signer, SignerPool}

  setup do
    runtime = :"railgun_test_#{System.unique_integer([:positive])}"
    start_supervised!({RailgunElixir.Runtime, name: runtime})
    {:ok, runtime: runtime}
  end

  test "native bridge responds and returns Sepolia chain config", %{runtime: runtime} do
    assert :ok = RailgunElixir.health(runtime)
    assert {:ok, chain} = RailgunElixir.chain_config(runtime, 11_155_111)
    assert chain.id == 11_155_111
    assert chain.wrapped_base_token == "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
    assert chain.unshield_fee_bps == 25
    assert chain.privacy_paymaster == "0xBb9D6507B5dE027dEb0196c83A7DC6Eef325bEe4"
    assert chain.railgun_fee_adapter == "0xeBabF510f824a349a9Be7F40cad3486B7249b1e0"
  end

  test "unsupported chain returns a structured native error", %{runtime: runtime} do
    assert {:error, error} = RailgunElixir.chain_config(runtime, 999_999_999)
    assert error.kind == :native
    assert error.message =~ "unsupported chain id"
  end

  test "signer paths match upstream Railgun derivation paths" do
    assert Signer.spending_key_path(2) == "m/44'/1984'/0'/0'/2'"
    assert Signer.viewing_key_path(2) == "m/420'/1984'/0'/0'/2'"
  end

  test "native signer creates a Railgun address", %{runtime: runtime} do
    assert {:ok, signer} = Signer.random(runtime, 11_155_111)
    assert signer.id =~ "signer-"
    assert signer.address =~ "0zk"
    assert signer.chain_id == 11_155_111
  end

  test "database adapter prefixes host storage keys" do
    {:ok, storage} = KohakuPlugins.MemoryStorage.start_link()

    host =
      KohakuPlugins.Host.new(
        storage: storage,
        keystore: KohakuPlugins.StaticKeystore.new("seed"),
        provider: %{rpc_url: "http://127.0.0.1:8545"}
      )

    adapter = DatabaseAdapter.new("11155111", host)

    assert :ok = DatabaseAdapter.set(adapter, "abc", "def")
    assert {:ok, "def"} = KohakuPlugins.Host.storage_get(host, "11155111:abc")
    assert :ok = DatabaseAdapter.delete(adapter, "abc")
    assert {:ok, ""} = DatabaseAdapter.get(adapter, "abc")
  end

  test "signer pool drains ERC20 balances across signers", %{runtime: runtime} do
    assert {:ok, signer1} = Signer.random(runtime, 11_155_111)
    assert {:ok, signer2} = Signer.random(runtime, 11_155_111)
    assert {:ok, weth} = Asset.erc20("0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14")
    assert {:ok, requested} = AssetAmount.new(weth, 12)
    pool = signer1 |> SignerPool.new() |> SignerPool.add(signer2)

    balances = %{
      signer1.id => [%AssetAmount{asset: weth, amount: 5}],
      signer2.id => [%AssetAmount{asset: weth, amount: 10}]
    }

    assert {:ok, entries} =
             SignerPool.drain_with_balances(pool, [requested], fn signer ->
               {:ok, Map.fetch!(balances, signer.id)}
             end)

    assert Enum.map(entries, & &1.amount) == [5, 7]
    assert Enum.map(entries, & &1.signer.id) == [signer1.id, signer2.id]
  end
end

defmodule RailgunPluginTest do
  use ExUnit.Case, async: false

  alias KohakuPlugins.{Asset, AssetAmount, Host, MemoryStorage, StaticKeystore}
  alias RailgunElixir.{Builder, Plugin, Provider, Signer, SignerPool, UtxoSyncer}

  @wallet_address "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
  @smart_account_signer_pk "0xd01165bc18d3f0d0b2114a42930164f729ae8310f447b4dd2e96124c02bbe151"
  @alto_executor "0x8dee56a37d5d7e6dedcbf09865b42d4e8c4ae74a"
  @alto_utility "0xe567a07c0a9d289a26b20582b3c3c05b97e07492"
  @entry_point_08 "0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108"

  setup do
    runtime = :"railgun_integration_#{System.unique_integer([:positive])}"
    start_supervised!({RailgunElixir.Runtime, name: runtime})
    {:ok, runtime: runtime}
  end

  test "plugin-sync flow mirrors upstream test", %{runtime: runtime} do
    with_integration(runtime, fn %{provider: provider} ->
      {:ok, storage} = MemoryStorage.start_link()

      host =
        Host.new(
          storage: storage,
          keystore: StaticKeystore.new("railgun-plugin-sync"),
          provider: provider
        )

      assert {:ok, plugin} = Plugin.create(host, runtime: runtime, rpc_batch_size: 10_000)
      assert {:ok, balances} = Plugin.balance(plugin, nil)
      assert is_list(balances)
      assert {:ok, notes} = Plugin.notes(plugin)
      assert is_list(notes)
    end)
  end

  test "transact-utxo flow mirrors upstream test", %{runtime: runtime} do
    with_integration(runtime, fn %{provider: eth_provider, chain: chain} ->
      assert {:ok, weth} = RailgunElixir.erc20(chain.wrapped_base_token)
      assert {:ok, railgun} = railgun_provider(runtime, eth_provider, chain, 1_000)
      assert {:ok, account1} = Signer.random(runtime, chain.id)
      assert {:ok, account2} = Signer.random(runtime, chain.id)
      assert :ok = Provider.sync(railgun)
      assert :ok = Provider.register(railgun, account1)
      assert :ok = Provider.register(railgun, account2)

      {:ok, txs} =
        railgun
        |> Provider.shield()
        |> RailgunElixir.ShieldBuilder.shield_native(account1.address, 1_000_000)
        |> RailgunElixir.ShieldBuilder.build()

      send_all(eth_provider, txs)
      assert :ok = Provider.sync(railgun)
      assert balance_for(railgun, account1.address, weth) == 997_500
      assert balance_for(railgun, account2.address, weth) == nil

      builder =
        railgun
        |> Provider.transact()
        |> RailgunElixir.TransactionBuilder.transfer(
          account1,
          account2.address,
          weth,
          5_000,
          "test transfer"
        )

      assert {:ok, tx} = Provider.build(railgun, builder)
      send_all(eth_provider, [tx])
      assert :ok = Provider.sync(railgun)
      assert balance_for(railgun, account1.address, weth) == 992_500
      assert balance_for(railgun, account2.address, weth) == 5_000

      builder =
        railgun
        |> Provider.transact()
        |> RailgunElixir.TransactionBuilder.unshield(
          account1,
          "0xe03747a83e600c3ab6c2e16dd1989c9b419d3a86",
          weth,
          1_000
        )

      assert {:ok, tx} = Provider.build(railgun, builder)
      send_all(eth_provider, [tx])
      assert :ok = Provider.sync(railgun)
      assert balance_for(railgun, account1.address, weth) == 991_500
      assert balance_for(railgun, account2.address, weth) == 5_000
    end)
  end

  test "plugin-transact-broadcast flow mirrors upstream test", %{runtime: runtime} do
    with_integration(runtime, fn context ->
      if is_nil(context[:alto_url]) do
        assert true
      else
        %{provider: eth_provider, chain: chain, alto_url: alto_url} = context

        assert {:ok, weth} = RailgunElixir.erc20(chain.wrapped_base_token)
        assert {:ok, railgun} = railgun_provider(runtime, eth_provider, chain, 1_000)
        assert {:ok, signer1} = Signer.random(runtime, chain.id)
        assert {:ok, signer2} = Signer.random(runtime, chain.id)
        assert :ok = Provider.register(railgun, signer1)
        assert :ok = Provider.register(railgun, signer2)
        assert :ok = Provider.sync(railgun)

        plugin1 =
          %Plugin{chain: chain, provider: railgun, pool: SignerPool.new(signer1)}
          |> Plugin.put_bundler(alto_url)
          |> Plugin.put_smart_account_signer(@smart_account_signer_pk)

        plugin2 = %Plugin{chain: chain, provider: railgun, pool: SignerPool.new(signer2)}

        assert {:ok, native} = AssetAmount.new(Asset.native(), 1_000_000_000_000_000_000)
        assert {:ok, txs} = Plugin.prepare_shield(plugin1, native)
        send_all(eth_provider, txs)

        assert balance_for(plugin1, weth) == 997_500_000_000_000_000
        assert balance_for(plugin2, weth) == nil

        assert {:ok, amount} = AssetAmount.new(weth, 5_000)
        assert {:ok, op} = Plugin.prepare_transfer(plugin1, amount, signer2.address)
        assert :ok = Plugin.broadcast(plugin1, op)

        assert balance_for(plugin1, weth) < 997_499_999_999_995_000
        assert balance_for(plugin2, weth) == 5_000

        assert {:ok, op} =
                 Plugin.prepare_unshield(
                   plugin1,
                   amount,
                   "0x068e4fde667a572277f3bfa19e585aac6c2a98d5"
                 )

        assert :ok = Plugin.broadcast(plugin1, op)

        assert balance_for(plugin1, weth) < 997_499_999_999_990_000
      end
    end)
  end

  defp with_integration(runtime, fun) do
    case integration_context(runtime) do
      {:ok, context} ->
        try do
          fun.(context)
        after
          stop_port(context[:alto])
          stop_port(context[:anvil])
        end

      :skip ->
        assert true
    end
  end

  defp integration_context(runtime) do
    cond do
      System.get_env("INTEGRATION") != "1" -> :skip
      is_nil(System.get_env("RPC_URL_SEPOLIA")) -> :skip
      is_nil(System.find_executable("anvil")) -> :skip
      true -> start_integration_context(runtime)
    end
  end

  defp start_integration_context(runtime) do
    {:ok, chain} = RailgunElixir.chain_config_sepolia(runtime)
    anvil_port = free_port()

    anvil =
      start_port(System.find_executable("anvil"), [
        "--fork-url",
        System.fetch_env!("RPC_URL_SEPOLIA"),
        "--chain-id",
        "#{chain.id}",
        "--port",
        "#{anvil_port}"
      ])

    rpc_url = "http://127.0.0.1:#{anvil_port}"
    wait_for_rpc(rpc_url)
    {:ok, provider} = KohakuProvider.new(rpc_url, timeout_ms: 120_000)

    context = %{chain: chain, provider: provider, anvil: anvil}

    case System.get_env("ALTO_BINARY") || System.find_executable("alto") do
      nil ->
        {:ok, context}

      alto_binary ->
        KohakuProvider.anvil_set_balance(provider, @alto_executor, 1_000 * Integer.pow(10, 18))
        KohakuProvider.anvil_set_balance(provider, @alto_utility, 1_000 * Integer.pow(10, 18))
        alto_port = free_port()

        alto =
          start_port(alto_binary, [
            "--rpc-url",
            rpc_url,
            "--entrypoints",
            @entry_point_08,
            "--executor-private-keys",
            "0x4a3a02862ddcb260ed52d40ef03f8e3d78fa3d174b0ef333afdf1ffb4a648cd5",
            "--utility-private-key",
            "0xdd4b2564c83ff7de602c39ffda1146055dc1814b07c083d7971722384f1f01a6",
            "--port",
            "#{alto_port}",
            "--safe-mode",
            "false"
          ])

        {:ok, Map.merge(context, %{alto: alto, alto_url: "http://127.0.0.1:#{alto_port}"})}
    end
  end

  defp railgun_provider(runtime, eth_provider, chain, batch_size) do
    with {:ok, builder} <- Builder.new(runtime, chain, eth_provider) do
      builder
      |> Builder.with_utxo_syncer(
        UtxoSyncer.chained([
          UtxoSyncer.subsquid(chain),
          UtxoSyncer.rpc(chain, eth_provider, batch_size)
        ])
      )
      |> Builder.build()
    end
  end

  defp send_all(provider, txs) do
    Enum.each(txs, fn tx ->
      tx = %{tx | from: @wallet_address}
      assert {:ok, hash} = KohakuProvider.send_transaction(provider, tx)

      assert {:ok, _receipt} =
               KohakuProvider.wait_for_transaction(provider, hash, attempts: 180, delay_ms: 1_000)
    end)
  end

  defp balance_for(%Plugin{} = plugin, asset) do
    {:ok, balances} = Plugin.balance(plugin, nil)

    balances
    |> Enum.find(&(&1.asset == asset))
    |> case do
      nil -> nil
      balance -> balance.amount
    end
  end

  defp balance_for(%Provider{} = provider, address, asset) do
    {:ok, balances} = Provider.balance(provider, address)

    balances
    |> Enum.find(&(&1.asset == asset))
    |> case do
      nil -> nil
      balance -> balance.amount
    end
  end

  defp wait_for_rpc(rpc_url) do
    {:ok, provider} = KohakuProvider.new(rpc_url)

    Enum.reduce_while(1..120, :waiting, fn _attempt, _state ->
      case KohakuProvider.get_chain_id(provider) do
        {:ok, _chain_id} ->
          {:halt, :ok}

        {:error, _error} ->
          Process.sleep(500)
          {:cont, :waiting}
      end
    end)
  end

  defp start_port(command, args) do
    Port.open({:spawn_executable, command}, [
      :binary,
      :exit_status,
      args: args,
      cd: File.cwd!()
    ])
  end

  defp stop_port(nil), do: :ok

  defp stop_port(port) when is_port(port) do
    Port.close(port)
  rescue
    _error -> :ok
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end

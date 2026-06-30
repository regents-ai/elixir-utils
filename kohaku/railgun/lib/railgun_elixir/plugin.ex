defmodule RailgunElixir.Plugin do
  @moduledoc """
  Kohaku-style Railgun plugin wrapper.
  """

  alias KohakuPlugins.{Asset, AssetAmount, Host}

  alias RailgunElixir.{
    Builder,
    DatabaseAdapter,
    Error,
    Native,
    PrivateOperation,
    Provider,
    Signer,
    SignerPool,
    TransactionBuilder,
    UtxoSyncer
  }

  @enforce_keys [:chain, :provider, :pool]
  defstruct [:chain, :provider, :pool, :bundler_url, :smart_account_signer_private_key]

  @type t :: %__MODULE__{
          chain: RailgunElixir.ChainConfig.t(),
          provider: Provider.t(),
          pool: SignerPool.t(),
          bundler_url: String.t() | nil,
          smart_account_signer_private_key: String.t() | nil
        }

  @spec create(Host.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def create(%Host{} = host, opts \\ []) do
    runtime = Keyword.get(opts, :runtime, RailgunElixir)
    key_index = Keyword.get(opts, :key_index, 0)
    rpc_batch_size = Keyword.get(opts, :rpc_batch_size, 10)
    poi? = Keyword.get(opts, :poi, true)

    result =
      with {:ok, chain_id} <- KohakuProvider.get_chain_id(host.provider),
           {:ok, chain} <- RailgunElixir.chain_config(runtime, chain_id),
           {:ok, spending_key} <- Host.derive_at(host, Signer.spending_key_path(key_index)),
           {:ok, viewing_key} <- Host.derive_at(host, Signer.viewing_key_path(key_index)),
           {:ok, builder} <- Builder.new(runtime, chain, host.provider) do
        _adapter = DatabaseAdapter.new(Integer.to_string(chain_id), host)

        syncer =
          UtxoSyncer.chained([
            UtxoSyncer.subsquid(chain),
            UtxoSyncer.rpc(chain, host.provider, rpc_batch_size)
          ])

        builder =
          builder
          |> Builder.with_utxo_syncer(syncer)
          |> maybe_enable_poi(poi?)

        with {:ok, provider} <- Builder.build(builder),
             {:ok, signer} <- Signer.private_key(runtime, spending_key, viewing_key, chain_id),
             :ok <- Provider.register(provider, signer) do
          {:ok, %__MODULE__{chain: chain, provider: provider, pool: SignerPool.new(signer)}}
        end
      end

    normalize_result(result)
  end

  @spec put_bundler(t(), String.t()) :: t()
  def put_bundler(%__MODULE__{} = plugin, bundler_url) when is_binary(bundler_url),
    do: %{plugin | bundler_url: bundler_url}

  @spec put_smart_account_signer(t(), String.t()) :: t()
  def put_smart_account_signer(%__MODULE__{} = plugin, private_key) when is_binary(private_key),
    do: %{plugin | smart_account_signer_private_key: private_key}

  @spec add_internal_signer(t(), String.t(), String.t()) :: {:ok, t()} | {:error, Error.t()}
  def add_internal_signer(%__MODULE__{} = plugin, spending_key, viewing_key) do
    with {:ok, signer} <-
           Signer.private_key(plugin.provider.runtime, spending_key, viewing_key, plugin.chain.id),
         :ok <- Provider.register(plugin.provider, signer) do
      {:ok, %{plugin | pool: SignerPool.add(plugin.pool, signer)}}
    end
  end

  @spec instance_id(t()) :: {:ok, String.t()}
  def instance_id(%__MODULE__{} = plugin), do: {:ok, SignerPool.primary(plugin.pool).address}

  @spec balance(t(), [Asset.t()] | nil) :: {:ok, [AssetAmount.t()]} | {:error, Error.t()}
  def balance(%__MODULE__{} = plugin, assets \\ nil) do
    with :ok <- Provider.sync(plugin.provider) do
      plugin.pool
      |> SignerPool.all()
      |> Enum.reduce_while({:ok, %{}}, fn signer, {:ok, acc} ->
        case Provider.balance(plugin.provider, signer.address) do
          {:ok, balances} -> {:cont, {:ok, merge_balances(acc, balances, assets)}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, balances} -> {:ok, Map.values(balances)}
        {:error, error} -> {:error, error}
      end
    end
  end

  @spec notes(t(), [Asset.t()]) :: {:ok, [RailgunElixir.Note.t()]} | {:error, Error.t()}
  def notes(%__MODULE__{} = plugin, assets \\ []) when is_list(assets) do
    with :ok <- Provider.sync(plugin.provider) do
      plugin.pool
      |> SignerPool.all()
      |> Enum.reduce_while({:ok, []}, fn signer, {:ok, acc} ->
        case Provider.notes(plugin.provider, signer.address) do
          {:ok, notes} ->
            notes =
              notes
              |> Enum.filter(&match?(%Asset{type: :erc20}, &1.asset))
              |> filter_notes(assets)

            {:cont, {:ok, acc ++ notes}}

          {:error, error} ->
            {:halt, {:error, error}}
        end
      end)
    end
  end

  @spec prepare_shield(t(), AssetAmount.t()) ::
          {:ok, [KohakuProvider.TxData.t()]} | {:error, Error.t()}
  def prepare_shield(%__MODULE__{} = plugin, %AssetAmount{} = asset),
    do: prepare_shield_multi(plugin, [asset])

  @spec prepare_shield_multi(t(), [AssetAmount.t()]) ::
          {:ok, [KohakuProvider.TxData.t()]} | {:error, Error.t()}
  def prepare_shield_multi(%__MODULE__{} = plugin, tokens) when is_list(tokens) do
    builder =
      Enum.reduce(tokens, Provider.shield(plugin.provider), fn token, builder ->
        add_shield(builder, SignerPool.primary(plugin.pool).address, token)
      end)

    RailgunElixir.ShieldBuilder.build(builder)
  end

  @spec prepare_transfer(t(), AssetAmount.t(), String.t()) ::
          {:ok, PrivateOperation.t()} | {:error, Error.t()}
  def prepare_transfer(%__MODULE__{} = plugin, %AssetAmount{} = token, to) when is_binary(to) do
    prepare_transfer_multi(plugin, [token], to)
  end

  @spec prepare_transfer_multi(t(), [AssetAmount.t()], String.t()) ::
          {:ok, PrivateOperation.t()} | {:error, Error.t()}
  def prepare_transfer_multi(%__MODULE__{} = plugin, tokens, to)
      when is_list(tokens) and is_binary(to) do
    with :ok <- require_erc20(tokens),
         {:ok, entries} <- SignerPool.drain(plugin.pool, plugin.provider, tokens) do
      builder =
        Enum.reduce(entries, Provider.transact(plugin.provider), fn entry, builder ->
          TransactionBuilder.transfer(builder, entry.signer, to, entry.asset, entry.amount, "")
        end)

      {:ok, %PrivateOperation{builder: builder}}
    end
  end

  @spec prepare_unshield(t(), AssetAmount.t(), String.t()) ::
          {:ok, PrivateOperation.t()} | {:error, Error.t()}
  def prepare_unshield(%__MODULE__{} = plugin, %AssetAmount{} = token, to) when is_binary(to) do
    prepare_unshield_multi(plugin, [token], to)
  end

  @spec prepare_unshield_multi(t(), [AssetAmount.t()], String.t()) ::
          {:ok, PrivateOperation.t()} | {:error, Error.t()}
  def prepare_unshield_multi(%__MODULE__{} = plugin, tokens, to)
      when is_list(tokens) and is_binary(to) do
    {erc20_tokens, native_amount} = normalize_unshield_tokens(plugin, tokens)

    with {:ok, entries} <- SignerPool.drain(plugin.pool, plugin.provider, erc20_tokens) do
      builder =
        Enum.reduce(entries, Provider.transact(plugin.provider), fn entry, builder ->
          TransactionBuilder.unshield(builder, entry.signer, to, entry.asset, entry.amount)
        end)

      {:ok, %PrivateOperation{builder: builder, native_amount: native_amount, to: to}}
    end
  end

  @spec broadcast(t(), PrivateOperation.t()) :: :ok | {:error, Error.t()}
  def broadcast(%__MODULE__{bundler_url: nil}, _op),
    do: {:error, Error.invalid_argument("bundler is required", %{})}

  def broadcast(%__MODULE__{smart_account_signer_private_key: nil}, _op),
    do: {:error, Error.invalid_argument("smart account signer is required", %{})}

  def broadcast(%__MODULE__{} = plugin, %PrivateOperation{} = op) do
    with {:ok, _result} <-
           Native.request(
             plugin.provider.runtime,
             "broadcast",
             %{
               provider_id: plugin.provider.id,
               operations: TransactionBuilder.to_native_operations(op.builder),
               bundler_url: plugin.bundler_url,
               smart_account_signer_private_key: plugin.smart_account_signer_private_key,
               chain_id: plugin.chain.id,
               rpc_url: plugin.provider.rpc_url,
               fee_payer_signer_id: SignerPool.primary(plugin.pool).id,
               fee_token: plugin.chain.wrapped_base_token,
               native_amount: op.native_amount || 0,
               to: op.to
             },
             900_000
           ),
         :ok <- Provider.sync(plugin.provider) do
      :ok
    end
  end

  defp maybe_enable_poi(builder, true), do: Builder.with_poi(builder)
  defp maybe_enable_poi(builder, false), do: builder

  defp add_shield(builder, recipient, %AssetAmount{asset: %Asset{type: :native}, amount: amount}),
    do: RailgunElixir.ShieldBuilder.shield_native(builder, recipient, amount)

  defp add_shield(builder, recipient, %AssetAmount{
         asset: %Asset{type: :erc20} = asset,
         amount: amount
       }),
       do: RailgunElixir.ShieldBuilder.shield(builder, recipient, asset, amount)

  defp merge_balances(acc, balances, nil), do: merge_balances(acc, balances, :all)

  defp merge_balances(acc, balances, assets) when is_list(assets) do
    allowed = MapSet.new(Enum.map(assets, &asset_key/1))

    balances
    |> Enum.filter(&(asset_key(&1.asset) in allowed))
    |> then(&merge_balances(acc, &1, :all))
  end

  defp merge_balances(acc, balances, :all) do
    Enum.reduce(balances, acc, fn %AssetAmount{} = balance, acc ->
      key = {asset_key(balance.asset), balance.tag}

      Map.update(acc, key, balance, fn existing ->
        %{existing | amount: existing.amount + balance.amount}
      end)
    end)
  end

  defp filter_notes(notes, []), do: notes

  defp filter_notes(notes, assets) do
    allowed = MapSet.new(Enum.map(assets, &asset_key/1))
    Enum.filter(notes, &(asset_key(&1.asset) in allowed))
  end

  defp require_erc20(tokens) do
    if Enum.all?(tokens, &match?(%AssetAmount{asset: %Asset{type: :erc20}}, &1)) do
      :ok
    else
      {:error, Error.unsupported("only ERC20 tokens are supported for this operation", %{})}
    end
  end

  defp normalize_unshield_tokens(plugin, tokens) do
    fee_bps = plugin.chain.unshield_fee_bps

    Enum.reduce(tokens, {[], 0}, fn
      %AssetAmount{asset: %Asset{type: :erc20}} = token, {tokens, native_amount} ->
        {[add_unshield_fee(token, fee_bps) | tokens], native_amount}

      %AssetAmount{asset: %Asset{type: :native}, amount: amount}, {tokens, native_amount} ->
        {:ok, wrapped} = Asset.erc20(plugin.chain.wrapped_base_token)
        token = add_unshield_fee(%AssetAmount{asset: wrapped, amount: amount}, fee_bps)
        {[token | tokens], native_amount + amount}
    end)
    |> then(fn {tokens, native_amount} -> {Enum.reverse(tokens), native_amount} end)
  end

  defp add_unshield_fee(%AssetAmount{amount: amount} = token, fee_bps) do
    denominator = 10_000 - fee_bps
    %{token | amount: div(amount * 10_000, denominator)}
  end

  defp asset_key(%Asset{type: :native}), do: {:native}

  defp asset_key(%Asset{type: type, contract: contract, token_id: token_id}),
    do: {type, contract, token_id}

  defp normalize_result({:ok, value}), do: {:ok, value}
  defp normalize_result({:error, error}), do: {:error, Error.from(error)}
  defp normalize_result(:ok), do: :ok
end

defmodule RailgunElixir.SignerPool do
  @moduledoc """
  Helper for spending balances across multiple Railgun signers.
  """

  alias KohakuPlugins.{Asset, AssetAmount}
  alias RailgunElixir.{Error, Provider, Signer}

  @enforce_keys [:signers]
  defstruct [:signers]

  @type drain_entry :: %{signer: Signer.t(), asset: Asset.t(), amount: non_neg_integer()}
  @type t :: %__MODULE__{signers: [Signer.t()]}

  @spec new(Signer.t()) :: t()
  def new(%Signer{} = primary), do: %__MODULE__{signers: [primary]}

  @spec add(t(), Signer.t()) :: t()
  def add(%__MODULE__{} = pool, %Signer{} = signer),
    do: %{pool | signers: pool.signers ++ [signer]}

  @spec primary(t()) :: Signer.t()
  def primary(%__MODULE__{signers: [primary | _rest]}), do: primary

  @spec all(t()) :: [Signer.t()]
  def all(%__MODULE__{signers: signers}), do: signers

  @spec drain(t(), Provider.t(), [AssetAmount.t()]) ::
          {:ok, [drain_entry()]} | {:error, Error.t()}
  def drain(%__MODULE__{} = pool, %Provider{} = provider, tokens) when is_list(tokens) do
    drain_with_balances(pool, tokens, fn signer -> Provider.balance(provider, signer.address) end)
  end

  @doc false
  @spec drain_with_balances(t(), [AssetAmount.t()], (Signer.t() ->
                                                       {:ok, [AssetAmount.t()]}
                                                       | {:error, Error.t()})) ::
          {:ok, [drain_entry()]} | {:error, Error.t()}
  def drain_with_balances(%__MODULE__{} = pool, tokens, balance_fun)
      when is_list(tokens) and is_function(balance_fun, 1) do
    remaining =
      Map.new(tokens, fn %AssetAmount{
                           asset: %Asset{type: :erc20, contract: contract},
                           amount: amount
                         } ->
        {contract, amount}
      end)

    with {:ok, entries, remaining} <- drain_signers(pool.signers, balance_fun, remaining, []) do
      case Enum.find(remaining, fn {_asset, amount} -> amount > 0 end) do
        nil ->
          {:ok, Enum.reverse(entries)}

        {asset, amount} ->
          {:error,
           Error.invalid_argument("insufficient balance", %{asset: asset, amount: amount})}
      end
    end
  end

  defp drain_signers([], _balance_fun, remaining, entries), do: {:ok, entries, remaining}

  defp drain_signers([signer | rest], balance_fun, remaining, entries) do
    with {:ok, balances} <- balance_fun.(signer) do
      {remaining, entries} =
        Enum.reduce(balances, {remaining, entries}, fn balance, {remaining, entries} ->
          drain_balance(signer, balance, remaining, entries)
        end)

      drain_signers(rest, balance_fun, remaining, entries)
    end
  end

  defp drain_balance(
         signer,
         %AssetAmount{asset: %Asset{type: :erc20, contract: contract} = asset, amount: balance},
         remaining,
         entries
       )
       when balance > 0 do
    need = Map.get(remaining, contract, 0)

    cond do
      need <= 0 ->
        {remaining, entries}

      true ->
        take = min(need, balance)

        {Map.put(remaining, contract, need - take),
         [%{signer: signer, asset: asset, amount: take} | entries]}
    end
  end

  defp drain_balance(_signer, _balance, remaining, entries), do: {remaining, entries}
end

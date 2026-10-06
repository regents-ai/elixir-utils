defmodule RegentCredits.Chains do
  @moduledoc """
  Where purchase money goes, and the wallet steps that send it.

    * Base: approve, then `depositUSDC` into REGENT staking with the purchase
      number attached. Staking passes it on to the treasury.
    * Ethereum: one USDC transfer straight to the Treasury Safe.

  The site names each chain's RPC and its chain client:

      config :regent_credits,
        chain_client: MySite.Chain.Client,
        chains: %{
          base: %{chain_id: 8453, name: "Base", rpc_url: "https://..."},
          ethereum: %{chain_id: 1, name: "Ethereum", rpc_url: "https://..."}
        }
  """

  alias RegentChain.{Call, Review}

  @usdc %{
    base: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
    ethereum: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
  }
  @staking "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
  @treasury "0x9fa152b0eadbfe9a7c5c0a8e1d11784f22669a3e"
  @source_tag "0x" <>
                Base.encode16(String.pad_trailing("regent.credits", 32, <<0>>), case: :lower)

  @doc "The chain as `RegentChain.Review` takes it."
  @spec chain(:base | :ethereum) :: RegentChain.Review.chain()
  def chain(name), do: :regent_credits |> Application.fetch_env!(:chains) |> Map.fetch!(name)

  @doc "The site's chain client (`RegentCredits.ChainClient`)."
  @spec client() :: module()
  def client, do: Application.fetch_env!(:regent_credits, :chain_client)

  @doc "USDC on the chain."
  @spec usdc(:base | :ethereum) :: String.t()
  def usdc(chain), do: Map.fetch!(@usdc, chain)

  @doc "REGENT staking on Base, which the Base approval lets take the USDC."
  @spec staking() :: String.t()
  def staking, do: @staking

  @doc "The Treasury Safe, the same address on Base and Ethereum. Refunds are sent from it."
  @spec treasury() :: String.t()
  def treasury, do: @treasury

  @doc """
  The wallet steps that buy `dollars` of Credits on `chain`. `number` is the
  purchase number the Base deposit carries.
  """
  @spec steps(:base | :ethereum, pos_integer(), Ecto.UUID.t()) :: [Review.transaction()]
  def steps(:base, dollars, number) do
    micro = micro(dollars)

    [
      Review.step(
        "approve",
        usdc(:base),
        Call.encode("approve(address,uint256)", [@staking, micro])
      ),
      Review.step(
        "buy",
        @staking,
        Call.encode("depositUSDC(uint256,bytes32,bytes32)", [
          micro,
          @source_tag,
          source_ref(number)
        ])
      )
    ]
  end

  def steps(:ethereum, dollars, _number) do
    [
      Review.step(
        "buy",
        usdc(:ethereum),
        Call.encode("transfer(address,uint256)", [@treasury, micro(dollars)])
      )
    ]
  end

  @doc "The step whose sent transaction is the purchase."
  @spec buy_step(:base | :ethereum, pos_integer(), Ecto.UUID.t()) :: Review.transaction()
  def buy_step(chain, dollars, number), do: chain |> steps(dollars, number) |> List.last()

  @doc "USDC's six-decimal units for whole dollars."
  @spec micro(pos_integer()) :: pos_integer()
  def micro(dollars), do: dollars * 1_000_000

  defp source_ref(number) do
    {:ok, bytes} = Ecto.UUID.dump(number)
    "0x" <> Base.encode16(<<0::128, bytes::binary>>, case: :lower)
  end
end

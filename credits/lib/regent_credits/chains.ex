defmodule RegentCredits.Chains do
  @moduledoc """
  Where purchase money goes, and the wallet steps that send it: on Base,
  approve, then `depositUSDC` into REGENT staking with the purchase number
  attached. Staking pays stakers their share of all REGENT and keeps the rest
  for the treasury.

  The site names Base's RPC and its chain client:

      config :regent_credits,
        chain_client: MySite.Chain.Client,
        chains: %{base: %{chain_id: 8453, name: "Base", rpc_url: "https://..."}}
  """

  alias RegentChain.{Call, Review}

  @usdc %{base: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"}
  @staking "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
  @treasury "0x9fa152b0eadbfe9a7c5c0a8e1d11784f22669a3e"
  @source_tag "0x" <>
                Base.encode16(String.pad_trailing("regent.credits", 32, <<0>>), case: :lower)

  @doc "The chain as `RegentChain.Review` takes it."
  @spec chain(:base) :: RegentChain.Review.chain()
  def chain(name), do: :regent_credits |> Application.fetch_env!(:chains) |> Map.fetch!(name)

  @doc "The site's chain client (`RegentCredits.ChainClient`)."
  @spec client() :: module()
  def client, do: Application.fetch_env!(:regent_credits, :chain_client)

  @doc "USDC on the chain."
  @spec usdc(:base) :: String.t()
  def usdc(chain), do: Map.fetch!(@usdc, chain)

  @doc "REGENT staking on Base, which the Base approval lets take the USDC."
  @spec staking() :: String.t()
  def staking, do: @staking

  @doc "The Treasury Safe on Base. Refunds are sent from it."
  @spec treasury() :: String.t()
  def treasury, do: @treasury

  @doc "The `bytes32` source tag every Credits deposit into REGENT staking carries."
  @spec source_tag() :: String.t()
  def source_tag, do: @source_tag

  @doc """
  The wallet steps that buy `dollars` of Credits on `chain`. `number` is the
  purchase number the Base deposit carries.
  """
  @spec steps(:base, pos_integer() | Decimal.t(), Ecto.UUID.t()) :: [
          Review.transaction()
        ]
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

  @doc "The step whose sent transaction is the purchase."
  @spec buy_step(:base, pos_integer() | Decimal.t(), Ecto.UUID.t()) ::
          Review.transaction()
  def buy_step(chain, dollars, number), do: chain |> steps(dollars, number) |> List.last()

  @doc "USDC's six-decimal units for an amount of dollars."
  @spec micro(pos_integer() | Decimal.t()) :: pos_integer()
  def micro(dollars), do: dollars |> Decimal.mult(1_000_000) |> Decimal.to_integer()

  defp source_ref(number) do
    {:ok, bytes} = Ecto.UUID.dump(number)
    "0x" <> Base.encode16(<<0::128, bytes::binary>>, case: :lower)
  end
end

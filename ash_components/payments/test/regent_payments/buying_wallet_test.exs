defmodule RegentPayments.BuyingWalletTest do
  @moduledoc """
  The buying wallet approves exactly the price to the sale, then sends the
  sale's own call, each signed with its key and sent to a fake Base. What
  comes back says whether the person's Credits go back or stay held.
  """

  use ExUnit.Case, async: false

  alias Ethers.Contracts.ERC20
  alias RegentPayments.BuyingWallet
  alias RegentPayments.Test.FakeBase
  alias RegentPayments.USDC

  @sale "0x" <> String.duplicate("c", 40)
  @call %{data: <<0x12, 0x34, 0x56, 0x78>>}

  defp buy(signer),
    do: BuyingWallet.buy(%{sale: @sale, price_atomic: 10_000_000, call: @call}, signer)

  test "the price is approved to the sale, then the sale's call is sent" do
    {chain, signer} = FakeBase.start(receipts: fn _hash -> "0x1" end)

    assert {:ok, %{approval: approval, call: call}} = buy(signer)
    assert {approval, call} == {FakeBase.hash(1), FakeBase.hash(2)}
    assert [approve, sale_call] = FakeBase.sent(chain)
    assert approve.to == String.downcase(USDC.asset())
    assert approve.input == ERC20.approve(@sale, 10_000_000).data
    assert sale_call.to == @sale
    assert sale_call.input == @call.data
  end

  test "an approval the chain refuses sends no call" do
    {chain, signer} = FakeBase.start(receipts: fn _hash -> "0x0" end)

    assert {:error, {:approval_failed, approval}} = buy(signer)
    assert approval == FakeBase.hash(1)
    assert [_approve] = FakeBase.sent(chain)
  end

  test "a call the sale refuses answers reverted, and one not yet mined may still land" do
    {_chain, signer} =
      FakeBase.start(receipts: fn hash -> if hash == FakeBase.hash(1), do: "0x1", else: "0x0" end)

    assert {:error, {:call_reverted, %{call: call}}} = buy(signer)
    assert call == FakeBase.hash(2)

    {_chain, signer} =
      FakeBase.start(receipts: fn hash -> if hash == FakeBase.hash(1), do: "0x1" end)

    assert {:error, {:call_unknown, %{call: call}}} = buy(signer)
    assert BuyingWallet.status(call, signer.rpc_url) == :not_yet
  end
end

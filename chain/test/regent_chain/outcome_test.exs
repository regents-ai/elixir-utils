defmodule RegentChain.OutcomeTest do
  use ExUnit.Case, async: true

  alias RegentChain.{BuilderCode, Call, Outcome, Review}

  @signer "0x1111111111111111111111111111111111111111"
  @usdc "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
  @chain %{chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"}

  # A chain that holds one confirmed transaction, whose calldata the test sets.
  defmodule Chain do
    def transaction(_chain, _hash), do: {:ok, Process.get(:sent)}
    def receipt(_chain, _hash), do: {:ok, %{"status" => "0x1"}}
  end

  setup do
    call = Call.encode("approve(address,uint256)", [@signer, 1_500_000])
    step = Review.step("approve", @usdc, call)
    {:ok, call: call, step: step, review: Review.new("approve", @signer, @chain, [step])}
  end

  defp sent(input) do
    Process.put(:sent, %{
      "chainId" => "0x2105",
      "from" => @signer,
      "to" => @usdc,
      "input" => input,
      "value" => "0x0"
    })
  end

  test "a step sent as built, or with the wallet's own code added, is that step", context do
    %{call: "0x" <> call, step: step, review: review} = context

    sent(step.data)
    assert Outcome.of(Chain, review, step, "0xhash") == {:ok, :confirmed}

    # The wallet rewrote the suffix to name its own code after ours.
    codes = "bc_u09360jo,baseapp"
    marker = String.duplicate("8021", 8)
    sent("0x" <> call <> Base.encode16(codes, case: :lower) <> "1300" <> marker)
    assert Outcome.of(Chain, review, step, "0xhash") == {:ok, :confirmed}
  end

  test "other calldata is not the step, with or without a code", %{step: step, review: review} do
    other = Call.encode("approve(address,uint256)", [@signer, 2_000_000])

    for input <- [other, BuilderCode.append(other)] do
      sent(input)
      assert Outcome.of(Chain, review, step, "0xhash") == {:error, :not_this_step}
    end
  end

  test "calldata without a suffix, or with a length longer than itself, is kept whole" do
    call = Call.encode("stake(uint256)", [5])
    assert BuilderCode.call(call) == call
    assert BuilderCode.call(BuilderCode.append(call)) == call

    too_long = call <> "ff00" <> String.duplicate("8021", 8)
    assert BuilderCode.call(too_long) == too_long
  end
end

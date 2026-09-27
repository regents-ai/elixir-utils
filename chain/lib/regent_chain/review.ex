defmodule RegentChain.Review do
  @moduledoc """
  The steps a page's wallet button sends, built on the server.

  Push the review to the page as soon as the figures it needs are known, and again
  whenever they change, so it is there before the button is pressed:

      review =
        RegentChain.Review.new(socket.assigns.id, wallet, base, [
          RegentChain.Review.step("approve", usdc, RegentChain.Call.encode("approve(address,uint256)", [pool, amount])),
          RegentChain.Review.step("stake", pool, RegentChain.Call.encode("stake(uint256)", [amount]))
        ])

      push_event(socket, "onchain-steps:review", review)

  Keep the review in assigns: `RegentChain.Outcome` checks a sent step against it.
  """

  alias RegentChain.Address

  @type chain :: %{chain_id: pos_integer(), name: String.t(), rpc_url: String.t()}
  @type step :: %{step: String.t(), to: String.t(), data: String.t(), value: String.t()}
  @type t :: %{component_id: String.t(), signer: String.t(), chain: chain(), steps: [step()]}

  @doc "A review for the component `component_id`, sent from `signer` on `chain`."
  @spec new(String.t(), String.t(), chain(), [step()]) :: t()
  def new(
        component_id,
        signer,
        %{chain_id: chain_id, name: name, rpc_url: "https://" <> _ = rpc_url},
        steps
      )
      when is_binary(component_id) and component_id != "" and is_integer(chain_id) and
             chain_id > 0 and
             is_binary(name) and name != "" and is_list(steps) do
    %{
      component_id: component_id,
      signer: Address.normalize!(signer),
      chain: %{chain_id: chain_id, name: name, rpc_url: rpc_url},
      steps: steps
    }
  end

  @doc """
  One step: its name on the page, the contract it calls, the calldata, and the
  native currency it sends in wei (none unless given).
  """
  @spec step(String.t(), String.t(), String.t(), non_neg_integer()) :: step()
  def step(name, to, "0x" <> hex = data, wei \\ 0)
      when is_binary(name) and name != "" and rem(byte_size(hex), 2) == 0 and is_integer(wei) and
             wei >= 0 do
    if match?({:ok, _bytes}, Base.decode16(hex, case: :mixed)) and byte_size(hex) >= 8 do
      %{
        step: name,
        to: Address.normalize!(to),
        data: String.downcase(data),
        value: "0x" <> String.downcase(Integer.to_string(wei, 16))
      }
    else
      raise ArgumentError, "not calldata: #{inspect(data)}"
    end
  end
end

defmodule RegentChain.Review do
  @moduledoc """
  The steps a page's wallet buttons send, built on the server for one signer.

  Push the review to the page as soon as the figures it needs are known, and again
  whenever they change, so it is there before the button is pressed:

      review =
        RegentChain.Review.new(socket.assigns.id, wallet, base, [
          RegentChain.Review.step("approve", usdc, RegentChain.Call.encode("approve(address,uint256)", [pool, amount])),
          RegentChain.Review.step("stake", pool, RegentChain.Call.encode("stake(uint256)", [amount]))
        ], %{"amount" => "12.5"})

      push_event(socket, "onchain-steps:review", %{component_id: socket.assigns.id, review: review})

  A review never changes once built. Its `id` is derived from everything in it
  (component, signer, chain, steps and the on-screen inputs it was built from), so
  the page reports each press against the exact review it sent from, and
  `RegentChain.Presses` checks the result against that review, never a later one.

  `inputs` are the form's values as the page shows them, as strings; the page
  compares them with the form at the press to tell whether the review still
  matches the screen.
  """

  alias RegentChain.Address

  @type chain :: %{chain_id: pos_integer(), name: String.t(), rpc_url: String.t()}
  @type transaction :: %{
          kind: String.t(),
          step: String.t(),
          to: String.t(),
          data: String.t(),
          value: String.t()
        }
  @type signature :: %{kind: String.t(), step: String.t(), typed_data: map()}
  @type step :: transaction() | signature()
  @type t :: %{
          id: String.t(),
          component_id: String.t(),
          signer: String.t(),
          chain: chain(),
          steps: [step()],
          inputs: %{String.t() => String.t()}
        }

  @doc """
  A review for the component `component_id`, sent from `signer` on `chain`.

  The chain's `rpc_url` is https, or http on this machine for a lab chain.
  """
  @spec new(String.t(), String.t(), chain(), [step()], %{String.t() => String.t()}) :: t()
  def new(
        component_id,
        signer,
        %{chain_id: chain_id, name: name, rpc_url: rpc_url},
        steps,
        inputs \\ %{}
      )
      when is_binary(component_id) and component_id != "" and is_integer(chain_id) and
             chain_id > 0 and is_binary(name) and name != "" and is_list(steps) and
             is_map(inputs) do
    unless rpc_url?(rpc_url), do: raise(ArgumentError, "not an RPC URL: #{inspect(rpc_url)}")

    unless Enum.all?(inputs, fn {key, value} -> is_binary(key) and is_binary(value) end),
      do: raise(ArgumentError, "inputs are strings named by strings: #{inspect(inputs)}")

    unless steps |> Enum.map(& &1.step) |> then(&(&1 == Enum.uniq(&1))),
      do: raise(ArgumentError, "two steps share a name")

    review = %{
      component_id: component_id,
      signer: Address.normalize!(signer),
      chain: %{chain_id: chain_id, name: name, rpc_url: rpc_url},
      steps: steps,
      inputs: inputs
    }

    Map.put(review, :id, id(review))
  end

  @doc """
  One transaction: its name on the page, the contract it calls, the calldata, and
  the native currency it sends in wei (none unless given).
  """
  @spec step(String.t(), String.t(), String.t(), non_neg_integer()) :: transaction()
  def step(name, to, "0x" <> hex = data, wei \\ 0)
      when is_binary(name) and name != "" and rem(byte_size(hex), 2) == 0 and is_integer(wei) and
             wei >= 0 do
    if match?({:ok, _bytes}, Base.decode16(hex, case: :mixed)) and byte_size(hex) >= 8 do
      %{
        kind: "transaction",
        step: name,
        to: Address.normalize!(to),
        data: String.downcase(data),
        value: "0x" <> String.downcase(Integer.to_string(wei, 16))
      }
    else
      raise ArgumentError, "not calldata: #{inspect(data)}"
    end
  end

  @doc """
  One EIP-712 signature: its name on the page and the typed data the wallet signs,
  as `eth_signTypedData_v4` takes it (`"domain"`, `"types"`, `"primaryType"` and
  `"message"`, JSON-ready). The server keeps the typed data; the page reports only
  the signature, and the server uses its own copy with it.
  """
  @spec signature(String.t(), map()) :: signature()
  def signature(
        name,
        %{"domain" => %{}, "types" => %{}, "primaryType" => primary, "message" => %{}} =
          typed_data
      )
      when is_binary(name) and name != "" and is_binary(primary) do
    %{kind: "signature", step: name, typed_data: typed_data}
  end

  @doc "The step named `name`, or `nil`."
  @spec find(t(), String.t()) :: step() | nil
  def find(%{steps: steps}, name), do: Enum.find(steps, &(&1.step == name))

  defp id(review) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(review, [:deterministic]))
    |> binary_part(0, 16)
    |> Base.url_encode64(padding: false)
  end

  defp rpc_url?("https://" <> _rest), do: true
  defp rpc_url?("http://127.0.0.1:" <> _rest), do: true
  defp rpc_url?("http://localhost:" <> _rest), do: true
  defp rpc_url?(_url), do: false
end

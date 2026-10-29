defmodule RegentPayments.BuyingWallet do
  @moduledoc """
  Buys something on the chain for a person with Regents' own USDC, after the
  person paid for it in purchased Credits. A small wallet on Base, whose key
  only this site holds, sends two transactions: an approval of exactly the
  price to the sale contract, then the sale's own call, which names the
  person's wallet as the receiver. What was bought goes straight to them.

  The site holds the Credits before it buys and settles the hold from what
  comes back. Until the sale's call is handed to the chain no USDC has left
  the wallet, so `{:approval_failed, hash}` gives the Credits back. After
  `{:call_reverted, sent}` the sale refused (sold out, price moved, closed)
  and nothing was bought. After `{:call_unknown, sent}` the purchase may
  still land: the site keeps the Credits held and reads the call's receipt
  with `status/2` until the chain answers, and never sends the call again.

  Each send takes the wallet's next nonce after any still waiting, so a buy
  never replaces an earlier one. A site sends one buy at a time, so two
  sends never read the same nonce.
  """

  alias Ethers.Contracts.ERC20
  alias RegentPayments.{Operator, USDC}

  @typedoc "A sale: its contract, the price in USDC atomic units, and its call, as raw bytes."
  @type buy :: %{sale: String.t(), price_atomic: pos_integer(), call: %{data: binary()}}

  @typedoc "The transactions a buy handed to the chain."
  @type sent :: %{approval: String.t(), call: String.t() | nil}

  @doc "Approves the price to the sale and sends its call, signed by `signer`."
  @spec buy(buy(), Operator.signer()) ::
          {:ok, sent()}
          | {:error,
             {:approval_failed, String.t() | nil}
             | {:call_reverted, sent()}
             | {:call_unknown, sent()}}
  def buy(%{sale: sale, price_atomic: price, call: call}, signer)
      when is_integer(price) and price > 0 do
    with {:ok, approval} <- approved(price, sale, signer) do
      called(send_call(call, sale, signer), signer, approval)
    end
  end

  @doc "What the chain says now of a call that may still land: `:ok`, `:reverted` or `:not_yet`."
  @spec status(String.t(), String.t()) :: :ok | :reverted | :not_yet
  defdelegate status(tx_hash, rpc_url), to: Operator

  defp approved(price, sale, signer) do
    case Operator.send(ERC20.approve(sale, price), USDC.asset(), signer) do
      {:ok, approval} -> approval_mined(Operator.mined(approval, signer), approval)
      {:error, _reason} -> {:error, {:approval_failed, nil}}
    end
  rescue
    _exception -> {:error, {:approval_failed, nil}}
  end

  defp approval_mined(:ok, approval), do: {:ok, approval}
  defp approval_mined({:error, _reason}, approval), do: {:error, {:approval_failed, approval}}

  # A refusal of the send may still have reached the chain, so it is treated
  # as a call that may land, like one that was sent and not yet mined.
  defp send_call(call, sale, signer) do
    Operator.send(call, sale, signer)
  rescue
    _exception -> {:error, :send_failed}
  end

  defp called({:ok, call}, signer, approval) do
    sent = %{approval: approval, call: call}

    case Operator.mined(call, signer) do
      :ok -> {:ok, sent}
      {:error, :reverted} -> {:error, {:call_reverted, sent}}
      {:error, :not_mined} -> {:error, {:call_unknown, sent}}
    end
  end

  defp called({:error, _reason}, _signer, approval),
    do: {:error, {:call_unknown, %{approval: approval, call: nil}}}
end

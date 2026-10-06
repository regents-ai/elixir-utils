defmodule RegentCredits.Refunds do
  @moduledoc """
  The work behind `RegentCredits.Refund`'s actions. `start/2` follows
  `RegentCredits.Ledger`'s order and reads whether the account has used
  Credits only after its accounts are locked, so a hold placed at the same
  moment is seen. `close/1` reads the chain outside any transaction.

  The refund rows and transfers are written by the library after the action
  was authorized, so they run unauthorized.
  """

  require Ash.Query

  alias RegentChain.{Abi, Address, Event}
  alias RegentCredits.{Chains, FirstUse, Ledger, Purchase, Refund}
  alias RegentCredits.Errors.{NotEnoughCredits, Refused}

  @doc "Takes the purchase's Credits out of the account, once."
  def start(purchase_id, actor) do
    # Internal: read by the authorized start action.
    case Ash.get(Purchase, purchase_id, authorize?: false) do
      {:ok, %{status: :credited} = purchase} -> take_out(purchase, actor)
      {:ok, _not_credited} -> refuse(:not_credited)
      {:error, _not_found} -> refuse(:not_found)
    end
  end

  defp take_out(purchase, actor) do
    owner = purchase.privy_user_id
    from = Ledger.identifier(:purchased, owner)
    to = Ledger.identifier(:regent_refunds, nil)
    accounts = Ledger.lock([to | Ledger.person(owner)])
    purchased = Ledger.balance_of(accounts, from)

    cond do
      refund = existing(purchase.id) ->
        {:ok, refund}

      used?(owner) ->
        refuse(:used)

      Decimal.lt?(purchased, purchase.amount) ->
        {:error, NotEnoughCredits.exception(shortfall: Decimal.sub(purchase.amount, purchased))}

      true ->
        Ledger.move(accounts, {from, to}, Decimal.new(purchase.amount), "refund:#{purchase.id}")
        record(purchase, actor)
    end
  end

  @doc """
  Marks the refund sent once `tx_hash` is a successful transaction moving
  exactly its USDC from the Treasury Safe to the wallet that paid.
  """
  def close(%{id: id, tx_hash: hash}) do
    # Internal: read by the authorized close action.
    refund = Ash.get!(Refund, id, authorize?: false)

    with {:ok, hash} <- hash |> Abi.hash() |> or_refuse(:refund_not_proven) do
      case refund do
        %{status: :sent, tx_hash: ^hash} -> {:ok, refund}
        %{status: :sent} -> refuse(:closed)
        %{status: :locked} -> prove_and_close(refund, hash)
      end
    end
  end

  defp prove_and_close(refund, hash) do
    with {:ok, receipt} <- Chains.client().receipt(Chains.chain(refund.chain), hash),
         :ok <- proves?(receipt, refund) do
      # Internal: written by the authorized close action.
      refund
      |> Ash.Changeset.for_update(:sent, %{tx_hash: hash}, authorize?: false)
      |> Ash.update()
    end
  end

  defp proves?(%{"status" => "0x1", "logs" => logs}, refund) do
    usdc = Chains.usdc(refund.chain)

    with {:ok, {[from, to], [value]}} <-
           Event.one(logs, "Transfer(address,address,uint256)", usdc, 2, 1),
         {:ok, from} <- Event.address(from),
         {:ok, to} <- Event.address(to),
         true <- Address.equal?(from, Chains.treasury()),
         true <- Address.equal?(to, refund.wallet),
         true <- value == Chains.micro(refund.amount) do
      :ok
    else
      _not_the_refund -> refuse(:refund_not_proven)
    end
  end

  defp proves?(_receipt, _refund), do: refuse(:refund_not_proven)

  defp record(purchase, actor) do
    # Internal: written by the authorized start action.
    Refund
    |> Ash.Changeset.for_create(
      :record,
      purchase
      |> Map.take([:privy_user_id, :wallet, :chain, :amount])
      |> Map.merge(%{purchase_id: purchase.id, started_by: actor.privy_user_id}),
      authorize?: false
    )
    |> Ash.create()
  end

  defp existing(purchase_id) do
    # Internal: read by the authorized start action.
    Refund
    |> Ash.Query.filter(purchase_id == ^purchase_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp used?(owner) do
    # Internal: read by the authorized start action, after the account is locked.
    FirstUse
    |> Ash.Query.filter(privy_user_id == ^owner)
    |> Ash.exists?(authorize?: false)
  end

  defp or_refuse({:ok, value}, _reason), do: {:ok, value}
  defp or_refuse(:error, reason), do: refuse(reason)

  defp refuse(reason), do: {:error, Refused.exception(reason: reason)}
end

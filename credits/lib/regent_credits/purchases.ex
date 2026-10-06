defmodule RegentCredits.Purchases do
  @moduledoc """
  The work behind `RegentCredits.Purchase`'s actions.

  `check/1` reads the chain outside any transaction, then credits in a
  transaction of its own (`credit/1`), which locks the person's accounts and
  re-reads the purchase so it credits once.

  The purchase rows are written by the library after the action was
  authorized, so they run unauthorized.
  """

  require Ash.Query

  alias RegentChain.{Abi, Address, Outcome}
  alias RegentCredits.{Chains, Ledger, Purchase}
  alias RegentCredits.Errors.Refused

  @ethereum_blocks 12
  @unknown_after_seconds 24 * 60 * 60

  @doc "Records a reported purchase; reporting the same one again answers with it."
  def report(%{privy_user_id: owner, chain: chain, tx_hash: hash} = args) do
    with {:ok, wallet} <- Address.normalize(args.wallet),
         {:ok, hash} <- Abi.hash(hash) do
      details = %{args | wallet: wallet, tx_hash: hash}

      case find(owner, chain, hash) do
        nil -> record(details)
        purchase -> same(purchase, details)
      end
    else
      :error -> {:error, Refused.exception(reason: :invalid_purchase)}
    end
  end

  @doc "Checks the purchase at the latest block and records what it found."
  def check(id) do
    case get(id) do
      %{status: :checking} = purchase -> read_chain(purchase)
      purchase -> {:ok, purchase}
    end
  end

  @doc "Adds the purchase's Credits as purchased Credits, once."
  def credit(id) do
    %{privy_user_id: owner} = get(id)
    Ledger.open(Ledger.person(owner))
    from = Ledger.identifier(:regent_purchases, nil)
    to = Ledger.identifier(:purchased, owner)
    accounts = Ledger.lock([from | Ledger.person(owner)])

    case get(id) do
      %{status: :checking} = purchase ->
        Ledger.move(accounts, {from, to}, Decimal.new(purchase.amount), "purchase:#{purchase.id}")
        finish(purchase, %{status: :credited, credited_at: DateTime.utc_now()})

      purchase ->
        {:ok, purchase}
    end
  end

  defp read_chain(purchase) do
    client = Chains.client()
    chain = Chains.chain(purchase.chain)
    step = Chains.buy_step(purchase.chain, purchase.amount, purchase.number)

    case Outcome.of(client, %{chain: chain, signer: purchase.wallet}, step, purchase.tx_hash) do
      {:ok, :confirmed} ->
        confirmed(purchase, client, chain)

      {:ok, :pending} ->
        pending(purchase)

      {:ok, :reverted} ->
        finish(purchase, %{status: :failed, reason: "reverted"})

      {:error, :not_this_step} ->
        finish(purchase, %{status: :failed, reason: "not this purchase"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp confirmed(%{chain: :base} = purchase, _client, _chain), do: run_credit(purchase)

  defp confirmed(%{chain: :ethereum} = purchase, client, chain) do
    with {:ok, %{"blockNumber" => number, "blockHash" => hash}} <-
           client.receipt(chain, purchase.tx_hash),
         {:ok, number} <- Abi.quantity(number),
         {:ok, hash} <- Abi.hash(hash),
         {:ok, head} <- client.block_number(chain) do
      cond do
        purchase.block_hash != hash -> seen(purchase, number, hash)
        head - number >= @ethereum_blocks -> run_credit(purchase)
        true -> {:ok, purchase}
      end
    else
      {:ok, nil} -> pending(purchase)
      :error -> {:error, :unreadable_receipt}
      {:error, reason} -> {:error, reason}
    end
  end

  defp pending(purchase) do
    cond do
      DateTime.diff(DateTime.utc_now(), purchase.inserted_at) > @unknown_after_seconds ->
        finish(purchase, %{status: :failed, reason: "not found"})

      purchase.block_hash ->
        seen(purchase, nil, nil)

      true ->
        {:ok, purchase}
    end
  end

  defp run_credit(purchase) do
    # Internal: the credit after an authorized check proved the payment.
    Purchase
    |> Ash.ActionInput.for_action(:credit, %{id: purchase.id}, authorize?: false)
    |> Ash.run_action()
  end

  defp record(details) do
    # Internal: written by the authorized report action.
    Purchase
    |> Ash.Changeset.for_create(:record, details, authorize?: false)
    |> Ash.create()
  end

  defp seen(purchase, number, hash) do
    # Internal: written by the authorized check.
    purchase
    |> Ash.Changeset.for_update(:seen, %{block_number: number, block_hash: hash},
      authorize?: false
    )
    |> Ash.update()
  end

  defp finish(purchase, fields) do
    # Internal: written by the authorized check.
    purchase
    |> Ash.Changeset.for_update(:finish, fields, authorize?: false)
    |> Ash.update()
  end

  defp same(purchase, details) do
    if Enum.all?([:wallet, :amount, :number], &(Map.get(purchase, &1) == details[&1])),
      do: {:ok, purchase},
      else: {:error, Refused.exception(reason: :key_reused)}
  end

  defp find(owner, chain, hash) do
    # Internal: read by the authorized report.
    Purchase
    |> Ash.Query.filter(privy_user_id == ^owner and chain == ^chain and tx_hash == ^hash)
    |> Ash.read_one!(authorize?: false)
  end

  defp get(id) do
    # Internal: read by the authorized check.
    Ash.get!(Purchase, id, authorize?: false)
  end
end

defmodule RegentCredits.Purchases do
  @moduledoc """
  The work behind `RegentCredits.Purchase`'s actions.

  `check/1` reads the chain outside any transaction, then credits in a
  transaction of its own (`credit/1`), which locks the person's accounts and
  re-reads the purchase so it credits once, and tells the site's
  `RegentCredits.Credited` module in that same transaction.

  `credit_deposit/1` credits a Base deposit `RegentCredits.Deposits` read
  from the chain, under the same lock, so a deposit and its report credit
  once between them. A report is saved under that lock too, so one wallet's
  payment in a transaction is never two purchases: a report finds the
  deposit the chain already credited and takes it, and a deposit finds the
  report and credits it. Two wallets paying in one transaction are two
  purchases.

  The purchase rows are written by the library after the action was
  authorized, so they run unauthorized.
  """

  require Ash.Query

  alias RegentChain.{Abi, Address, Outcome}
  alias RegentCredits.{Chains, Ledger, Purchase, Wallets}
  alias RegentCredits.Errors.Refused

  @ethereum_blocks 12
  @unknown_after_seconds 24 * 60 * 60

  @doc """
  Records a reported purchase once the chain holds its transaction, read
  outside any database transaction: one the reporting wallet sent as this
  purchase's Buy. Nothing is saved for a hash the chain does not hold yet,
  which the page reports again, or for one that is not this purchase.
  Reporting the same one again answers with it.
  """
  def report(%{privy_user_id: owner, chain: chain, tx_hash: hash} = args) do
    with {:ok, wallet} <- Address.normalize(args.wallet),
         {:ok, hash} <- Abi.hash(hash) do
      details = %{args | wallet: wallet, tx_hash: hash}

      case find(owner, chain, hash, wallet) do
        nil -> record_sent(details)
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
      %{status: :checking} = purchase -> credit_once(purchase, accounts, {from, to})
      purchase -> {:ok, purchase}
    end
  end

  @doc """
  Credits a wallet's deposit the chain holds, once: to the account holding the wallet
  that sent it, else to the account that reported it from that wallet, else
  under that wallet until an account attaches it. That account's report of
  the same transaction is credited with what the chain holds.

  The account is chosen before the lock and again under it. When an attach or
  a report changed it meanwhile, nothing is credited and the next read tries
  again.
  """
  def credit_deposit(%{chain: chain, tx_hash: hash, wallet: wallet} = deposit) do
    account = account(wallet, paid(chain, hash, wallet))
    {to, opened} = holder(account, wallet)
    Ledger.open(opened)
    from = Ledger.identifier(:regent_purchases, nil)
    accounts = Ledger.lock([from | opened])
    found = paid(chain, hash, wallet)

    cond do
      credited = Enum.find(found, &(&1.status == :credited)) ->
        {:ok, credited}

      account(wallet, found) != account ->
        {:error, :account_changed}

      true ->
        report = account && Enum.find(found, &(&1.privy_user_id == account))
        purchase = save_deposit(report, deposit, account)
        Ledger.move(accounts, {from, to}, purchase.amount, "purchase:#{purchase.id}")

        if account,
          do: :ok = Application.fetch_env!(:regent_credits, :on_credited).credited(purchase)

        {:ok, purchase}
    end
  end

  # The account holding the wallet, else the first to report the payment:
  # Outcome.sent proved the wallet sent it.
  defp account(wallet, found) do
    Map.get(Wallets.owners([wallet]), wallet) ||
      found
      |> Enum.filter(& &1.privy_user_id)
      |> Enum.min_by(& &1.inserted_at, DateTime, fn -> %{privy_user_id: nil} end)
      |> Map.fetch!(:privy_user_id)
  end

  @doc """
  Gives `owner` the credited deposits waiting under these wallets, and tells
  the site of each as it would of any credit. The caller has locked the
  waiting accounts, which every credit into them also locks, and moved the
  Credits. `owner` has no purchase of these payments: a report from the
  wallet takes its waiting deposit instead.
  """
  def claim(owner, addresses) do
    on_credited = Application.fetch_env!(:regent_credits, :on_credited)

    # Internal: written by the authorized attach action.
    Purchase
    |> Ash.Query.filter(is_nil(privy_user_id) and wallet in ^addresses and status == :credited)
    |> Ash.bulk_update!(:claim, %{privy_user_id: owner},
      return_records?: true,
      strategy: [:atomic, :stream],
      authorize?: false
    )
    |> Map.fetch!(:records)
    |> Enum.each(&(:ok = on_credited.credited(&1)))
  end

  defp holder(nil, wallet) do
    waiting = Ledger.identifier(:address_purchased, wallet)
    {waiting, [waiting]}
  end

  defp holder(account, _wallet),
    do: {Ledger.identifier(:purchased, account), Ledger.person(account)}

  defp save_deposit(nil, deposit, account) do
    # Internal: written by the credit of a deposit the chain holds.
    Purchase
    |> Ash.Changeset.for_create(:found, Map.put(deposit, :privy_user_id, account),
      authorize?: false
    )
    |> Ash.create!()
  end

  defp save_deposit(reported, deposit, _account) do
    # Internal: written by the credit of a deposit the chain holds.
    reported
    |> Ash.Changeset.for_update(:found_reported, Map.take(deposit, [:wallet, :amount, :number]),
      authorize?: false
    )
    |> Ash.update!()
  end

  # The purchases of what `wallet` paid in the transaction.
  defp paid(chain, hash, wallet) do
    # Internal: read by the credit of a deposit or a report, before and
    # after the lock.
    Purchase
    |> Ash.Query.filter(chain == ^chain and tx_hash == ^hash and wallet == ^wallet)
    |> Ash.read!(authorize?: false)
  end

  # Every credit locks regent_purchases, so a second row for the same
  # payment sees the first one's credit here.
  defp credit_once(purchase, accounts, pair) do
    if credited_elsewhere?(purchase) do
      finish(purchase, %{status: :failed, reason: "already credited"})
    else
      Ledger.move(accounts, pair, Decimal.new(purchase.amount), "purchase:#{purchase.id}")

      # Internal: written by the authorized credit. Not through decided/2: a
      # purchase that stopped being checked fails the credit, which rolls back
      # the move.
      credited =
        purchase
        |> Ash.Changeset.for_update(
          :finish,
          %{status: :credited, credited_at: DateTime.utc_now()},
          authorize?: false
        )
        |> Ash.update()

      with {:ok, purchase} <- credited do
        :ok = Application.fetch_env!(:regent_credits, :on_credited).credited(purchase)
        {:ok, purchase}
      end
    end
  end

  defp credited_elsewhere?(%{chain: chain, tx_hash: hash, wallet: wallet}) do
    # Internal: read by the authorized credit.
    Purchase
    |> Ash.Query.filter(
      chain == ^chain and tx_hash == ^hash and wallet == ^wallet and status == :credited
    )
    |> Ash.exists?(authorize?: false)
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

  defp record_sent(%{chain: chain, wallet: wallet, amount: amount, number: number} = details) do
    review = %{chain: Chains.chain(chain), signer: wallet}
    step = Chains.buy_step(chain, amount, number)

    case Outcome.sent(Chains.client(), review, step, details.tx_hash) do
      {:ok, :sent} -> record(details)
      {:ok, :unknown} -> {:error, Refused.exception(reason: :not_seen_yet)}
      {:error, :not_this_step} -> {:error, Refused.exception(reason: :not_this_purchase)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Under the lock every credit takes. The deposit waiting under the wallet,
  # if the chain's credit came first, goes to the person; a report of theirs
  # saved meanwhile answers as a repeat would.
  defp record(%{privy_user_id: owner, chain: chain, tx_hash: hash, wallet: wallet} = details) do
    from = Ledger.identifier(:regent_purchases, nil)
    waiting = Ledger.identifier(:address_purchased, wallet)
    to = Ledger.identifier(:purchased, owner)

    Ash.transact(Purchase, fn ->
      Ledger.open([waiting | Ledger.person(owner)])
      accounts = Ledger.lock([from, waiting | Ledger.person(owner)])
      found = paid(chain, hash, wallet)

      saved =
        cond do
          mine = Enum.find(found, &(&1.privy_user_id == owner)) ->
            same(mine, details)

          deposit = Enum.find(found, &is_nil(&1.privy_user_id)) ->
            Ledger.move(accounts, {waiting, to}, deposit.amount, "purchase:#{deposit.id}")
            take(deposit, owner)

          true ->
            # Internal: written by the authorized report action.
            Purchase
            |> Ash.Changeset.for_create(:record, details, authorize?: false)
            |> Ash.create()
        end

      # Ash.transact wraps the purchase in {:ok, _} and rolls back an error.
      with {:ok, purchase} <- saved, do: purchase
    end)
  end

  defp take(deposit, owner) do
    # Internal: written by the authorized report action.
    purchase =
      deposit
      |> Ash.Changeset.for_update(:claim, %{privy_user_id: owner}, authorize?: false)
      |> Ash.update!()

    :ok = Application.fetch_env!(:regent_credits, :on_credited).credited(purchase)
    {:ok, purchase}
  end

  defp seen(purchase, number, hash) do
    # Internal: written by the authorized check.
    purchase
    |> Ash.Changeset.for_update(:seen, %{block_number: number, block_hash: hash},
      authorize?: false
    )
    |> Ash.update()
    |> decided(purchase)
  end

  defp finish(purchase, fields) do
    # Internal: written by the authorized check.
    purchase
    |> Ash.Changeset.for_update(:finish, fields, authorize?: false)
    |> Ash.update()
    |> decided(purchase)
  end

  # A deposit read from the chain credited the purchase while it was checked.
  defp decided(
         {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}},
         purchase
       ),
       do: {:ok, get(purchase.id)}

  defp decided(result, _purchase), do: result

  defp same(purchase, details) do
    if purchase.number == details.number and Decimal.eq?(purchase.amount, details.amount),
      do: {:ok, purchase},
      else: {:error, Refused.exception(reason: :key_reused)}
  end

  defp find(owner, chain, hash, wallet) do
    # Internal: read by the authorized report.
    Purchase
    |> Ash.Query.filter(
      privy_user_id == ^owner and chain == ^chain and tx_hash == ^hash and wallet == ^wallet
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp get(id) do
    # Internal: read by the authorized check.
    Ash.get!(Purchase, id, authorize?: false)
  end
end

defmodule RegentCredits.Holds do
  @moduledoc """
  The work behind `RegentCredits.Hold`'s actions. Each runs inside the action's
  transaction and follows `RegentCredits.Ledger`'s order: lock every account
  it touches, read, then move. The hold row is read again after the lock, so
  two closes of one hold never both act.

  The hold row and its transfers are written by the library itself after the
  action was authorized, so they run unauthorized.
  """

  require Ash.Query

  alias RegentCredits.{AgentSpending, Amount, FirstUse, Hold, Ledger, Wallets}
  alias RegentCredits.Errors.{NotEnoughCredits, Refused}

  @bounty_share 90

  @doc "Sets aside the amount: given Credits first, then purchased."
  def hold(%{key: key, privy_user_id: owner, amount: amount, purpose: purpose}, actor) do
    agent = if actor.role == :agent, do: actor.agent_address

    details = %{
      privy_user_id: owner,
      amount: amount,
      purpose: purpose,
      agent_address: agent,
      pairing_id: if(actor.role == :agent, do: actor.pairing_id)
    }

    with :ok <- valid_amount(amount),
         accounts = owner |> Ledger.person() |> Ledger.lock(),
         :ok <- AgentSpending.current_pairing(actor) do
      case find(actor.site, key) do
        nil -> place(accounts, actor, key, details)
        hold -> same(hold, details)
      end
    end
  end

  defp place(accounts, actor, key, details) do
    %{privy_user_id: owner, amount: amount} = details
    given = Ledger.balance_of(accounts, Ledger.identifier(:given, owner))
    purchased = Ledger.balance_of(accounts, Ledger.identifier(:purchased, owner))
    available = Decimal.add(given, purchased)

    with :ok <- AgentSpending.allow(actor, details),
         :ok <- enough(available, amount) do
      from_given = Decimal.min(given, amount)
      from_purchased = Decimal.sub(amount, from_given)
      operation = "hold:#{actor.site}:#{key}"

      accounts
      |> Ledger.move(pair(:given, :held_given, owner), from_given, operation)
      |> Ledger.move(pair(:purchased, :held_purchased, owner), from_purchased, operation)

      # Internal: written by the authorized hold action.
      FirstUse
      |> Ash.Changeset.for_create(:record, %{privy_user_id: owner, hold_key: key},
        authorize?: false
      )
      |> Ash.create!()

      # Internal: written by the authorized hold action.
      Hold
      |> Ash.Changeset.for_create(
        :record,
        Map.merge(details, %{
          site: actor.site,
          key: key,
          given: from_given,
          purchased: from_purchased
        }),
        authorize?: false
      )
      |> Ash.create()
    end
  end

  @doc "Returns all of a hold, each part as the kind it was taken from."
  def give_back(%{key: key, reason: reason}, actor) do
    close(actor, key, {%{status: :given_back}, %{reason: reason}}, [], fn hold, accounts ->
      give(accounts, hold, hold.given, hold.purchased)
      {:ok, %{returned: hold.amount, used: 0, forfeited: 0}}
    end)
  end

  @doc "Turns all of a hold into revenue."
  def charge(%{key: key}, actor) do
    close(actor, key, {%{status: :charged}, %{}}, [revenue()], fn hold, accounts ->
      to_revenue(accounts, hold, hold.given, hold.purchased)
      {:ok, %{returned: 0, used: hold.amount, forfeited: 0}}
    end)
  end

  @doc """
  Moves a hold's Credits, untouched, to a new hold under `to_key`. Nothing is
  charged, the person's balance does not change, and the new hold keeps the
  time the Credits were first held.
  """
  def carry_over(%{key: key, to_key: to_key}, _actor) when key == to_key,
    do: {:error, Refused.exception(reason: :same_key)}

  def carry_over(%{key: key, to_key: to_key, purpose: purpose}, actor) do
    closing = {%{status: :carried_over, carried_to: to_key}, %{}}

    with {:ok, closed} <- close(actor, key, closing, [], fn _hold, _accounts -> {:ok, %{}} end) do
      carried =
        closed
        |> Map.take([
          :privy_user_id,
          :agent_address,
          :pairing_id,
          :amount,
          :given,
          :purchased,
          :held_at
        ])
        |> Map.put(:purpose, purpose)

      # A hold already under `to_key` is this carry made before, or the key is
      # taken; refusing rolls the close back, so no Credits are left unheld.
      case find(actor.site, to_key) do
        nil -> carry(carried, actor.site, to_key)
        hold -> same(hold, carried)
      end
    end
  end

  defp carry(carried, site, key) do
    # Internal: written by the authorized carry_over action.
    Hold
    |> Ash.Changeset.for_create(:record, Map.merge(carried, %{site: site, key: key}),
      authorize?: false
    )
    |> Ash.create()
  end

  @doc """
  Closes an Offer's hold once: `returned` comes back, `used` and `forfeited`
  are revenue. Given Credits were spent first, so the used and forfeited part
  is taken from them first and what comes back is purchased first.
  """
  def settle(%{key: key, returned: returned, used: used, forfeited: forfeited} = args, actor) do
    figures = %{returned: returned, used: used, forfeited: forfeited}
    closing = {Map.put(figures, :status, :settled), %{reason: args[:reason]}}

    close(actor, key, closing, [revenue()], fn hold, accounts ->
      kept = Decimal.add(used, forfeited)

      if Enum.all?(Map.values(figures), &Amount.part?/1) and
           Decimal.eq?(Decimal.add(returned, kept), hold.amount) do
        kept_given = Decimal.min(hold.given, kept)
        kept_purchased = Decimal.sub(kept, kept_given)

        accounts
        |> to_revenue(hold, kept_given, kept_purchased)
        |> give(
          hold,
          Decimal.sub(hold.given, kept_given),
          Decimal.sub(hold.purchased, kept_purchased)
        )

        {:ok, figures}
      else
        {:error, Refused.exception(reason: :split_mismatch)}
      end
    end)
  end

  @doc """
  Pays a bounty: 90% to `to` as given Credits, the rest is revenue. `to` is a
  Privy account id, or a wallet address: paid to the account holding that
  wallet, or kept under the address until an account with it signs in.
  """
  def pay_bounty(%{key: key, to: to}, actor) do
    recipient = recipient(to)
    closing = {%{status: :bounty_paid, paid_to: to}, %{}}

    close(actor, key, closing, [recipient, revenue()], fn hold, accounts ->
      split_bounty(accounts, hold, recipient)
    end)
  end

  @doc "Returns an unanswered bounty to the asker at the same 90/10, as given Credits."
  def take_back(%{key: key}, actor) do
    close(actor, key, {%{status: :taken_back}, %{}}, [revenue()], fn hold, accounts ->
      split_bounty(accounts, hold, Ledger.identifier(:given, hold.privy_user_id))
    end)
  end

  defp split_bounty(accounts, hold, recipient) do
    share = Amount.share(hold.amount, @bounty_share)
    share_given = Decimal.min(hold.given, share)
    share_purchased = Decimal.sub(share, share_given)
    owner = hold.privy_user_id

    accounts
    |> Ledger.move(
      {Ledger.identifier(:held_given, owner), recipient},
      share_given,
      operation(hold)
    )
    |> Ledger.move(
      {Ledger.identifier(:held_purchased, owner), recipient},
      share_purchased,
      operation(hold)
    )
    |> to_revenue(
      hold,
      Decimal.sub(hold.given, share_given),
      Decimal.sub(hold.purchased, share_purchased)
    )

    {:ok, %{returned: 0, used: hold.amount, forfeited: 0}}
  end

  @doc """
  Locks, in one sorted statement, the accounts of everyone owning a hold under
  `keys` or named in `privy_user_ids`, and the revenue account. A site that
  holds and closes holds for several people in one transaction calls this
  first, so each later call re-locks rows the transaction already holds and
  never waits on another such transaction in the opposite order. A bounty's
  recipient is not among them.
  """
  def lock_holds(%{keys: keys, privy_user_ids: privy_user_ids}, actor) do
    # Internal: read by the authorized operation.
    owners =
      Hold
      |> Ash.Query.filter(site == ^actor.site and key in ^keys)
      |> Ash.Query.select([:privy_user_id])
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.privy_user_id)

    (owners ++ privy_user_ids)
    |> Enum.uniq()
    |> Enum.flat_map(&Ledger.person/1)
    |> Enum.concat([revenue()])
    |> Ledger.lock()

    :ok
  end

  # Locks the owner's accounts and the `others` the close moves Credits to,
  # re-reads the hold, and closes it once. `closing` is the fields a repeat must
  # match, then the fields only the first close writes. A repeat answers with
  # the closed hold; any other close of a closed hold is refused.
  defp close(actor, key, {closing, note}, others, work) do
    with {:ok, %{privy_user_id: owner}} <- fetch(actor.site, key) do
      open_recipients(others)
      accounts = Ledger.lock(Ledger.person(owner) ++ others)
      actor.site |> find(key) |> close_once(accounts, closing, note, work)
    end
  end

  defp close_once(%{status: :held} = hold, accounts, closing, note, work) do
    with {:ok, figures} <- work.(hold, accounts) do
      write_close(hold, closing |> Map.merge(note) |> Map.merge(figures))
    end
  end

  defp close_once(hold, _accounts, closing, _note, _work) do
    if Enum.all?(closing, fn {field, value} -> equal?(Map.get(hold, field), value) end),
      do: {:ok, hold},
      else: {:error, Refused.exception(reason: :closed)}
  end

  defp write_close(hold, fields) do
    # Internal: written by the authorized closing action.
    hold
    |> Ash.Changeset.for_update(:close, Map.put(fields, :closed_at, DateTime.utc_now()),
      authorize?: false
    )
    |> Ash.update()
  end

  defp give(accounts, hold, given, purchased) do
    owner = hold.privy_user_id

    accounts
    |> Ledger.move(pair(:held_given, :given, owner), given, operation(hold))
    |> Ledger.move(pair(:held_purchased, :purchased, owner), purchased, operation(hold))
  end

  defp to_revenue(accounts, hold, given, purchased) do
    owner = hold.privy_user_id

    accounts
    |> Ledger.move({Ledger.identifier(:held_given, owner), revenue()}, given, operation(hold))
    |> Ledger.move(
      {Ledger.identifier(:held_purchased, owner), revenue()},
      purchased,
      operation(hold)
    )
  end

  defp recipient("0x" <> _rest = address) do
    address = String.downcase(address)

    case Wallets.owners([address]) do
      %{^address => privy_user_id} -> Ledger.identifier(:given, privy_user_id)
      %{} -> Ledger.identifier(:address_given, address)
    end
  end

  defp recipient(privy_user_id), do: Ledger.identifier(:given, privy_user_id)

  # The Regent accounts already exist; a recipient's open on first use.
  defp open_recipients(identifiers) do
    identifiers
    |> Enum.flat_map(fn
      "given/" <> privy_user_id -> Ledger.person(privy_user_id)
      "address_given/" <> _address = account -> [account]
      _regent -> []
    end)
    |> Ledger.open()
  end

  defp same(hold, details) do
    if Enum.all?(details, fn {field, value} -> equal?(Map.get(hold, field), value) end),
      do: {:ok, hold},
      else: {:error, Refused.exception(reason: :key_reused)}
  end

  defp equal?(%Decimal{} = a, %Decimal{} = b), do: Decimal.eq?(a, b)
  defp equal?(a, b), do: a == b

  defp fetch(site, key) do
    case find(site, key) do
      nil -> {:error, Refused.exception(reason: :not_found)}
      hold -> {:ok, hold}
    end
  end

  defp find(site, key) do
    # Internal: read by the authorized operation.
    Hold
    |> Ash.Query.filter(site == ^site and key == ^key)
    |> Ash.read_one!(authorize?: false)
  end

  defp enough(available, amount) do
    if Decimal.lt?(available, amount),
      do: {:error, NotEnoughCredits.exception(shortfall: Decimal.sub(amount, available))},
      else: :ok
  end

  defp valid_amount(amount) do
    if Amount.valid?(amount), do: :ok, else: {:error, Refused.exception(reason: :invalid_amount)}
  end

  defp revenue, do: Ledger.identifier(:regent_revenue, nil)
  defp pair(from, to, owner), do: {Ledger.identifier(from, owner), Ledger.identifier(to, owner)}
  defp operation(hold), do: "hold:#{hold.site}:#{hold.key}"
end

defmodule RegentCredits.Ledger do
  @moduledoc """
  Locking and moving ledger accounts inside one database transaction.

  Every operation follows the same order, which keeps it correct when sites
  on several machines move the same accounts at once:

    1. `lock/1` every account the operation will touch, sorted by id, in a
       statement of its own. Locking after a transfer is written deadlocks,
       because the transfer's foreign keys already hold a share lock on both
       accounts.
    2. Read balances only after the lock, in a new statement, so they include
       everything committed while the lock was awaited.
    3. `move/4` the Credits.

  A site that locks its own rows first (an Offer slot, say) calls the
  operation after them, never before.

  Each operation's lock covers only its own accounts. A site that runs several
  operations for different people in one transaction (settling an Offer slot
  holds, gives back and settles several bidders' holds) calls
  `RegentCredits.lock_holds/3` first, with every hold it may close and every
  person it may hold for, so the whole set is locked once, in order.

  Callers have authorized the operation itself; these internal reads and
  writes run unauthorized for that reason.
  """

  require Ash.Query

  alias RegentCredits.Amount
  alias RegentCredits.Ledger.{Account, Transfer}

  @regent [:regent_purchases, :regent_gifts, :regent_revenue, :regent_refunds]
  @person [:given, :purchased, :held_given, :held_purchased]
  @person_kinds Enum.map(@person, &Atom.to_string/1)

  @doc "The ledger identifier of an account."
  @spec identifier(atom(), String.t() | nil) :: String.t()
  def identifier(kind, nil) when kind in @regent, do: Atom.to_string(kind)
  def identifier(kind, privy_user_id) when kind in @person, do: "#{kind}/#{privy_user_id}"

  def identifier(kind, address) when kind in [:address_given, :address_purchased],
    do: "#{kind}/#{String.downcase(address)}"

  @doc "The four identifiers of a Privy account."
  @spec person(String.t()) :: [String.t()]
  def person(privy_user_id), do: Enum.map(@person, &identifier(&1, privy_user_id))

  @doc """
  Opens any of these accounts that do not exist yet. The Regent accounts are
  opened by the library's migrations; a person's accounts open when Credits
  first reach them.

  Opening runs before an operation's locks and must not take any itself: an
  upsert would lock the existing rows out of `lock/1`'s order (and Ash's
  upsert on PostgreSQL 17 is a `MERGE`, which also fails on a concurrent
  insert instead of waiting for it). So this is the library's one direct
  repository call: `INSERT ... ON CONFLICT DO NOTHING`, which leaves existing
  rows unlocked and waits for an account another transaction is opening.
  """
  @spec open([String.t()]) :: :ok
  def open([]), do: :ok

  def open(identifiers) do
    rows =
      identifiers |> Enum.uniq() |> Enum.sort() |> Enum.map(&%{identifier: &1, currency: "XRC"})

    RegentCredits.repo(Account, :create).insert_all({"accounts", Account}, rows,
      prefix: "regent_credits",
      on_conflict: :nothing,
      conflict_target: [:identifier]
    )

    :ok
  end

  @doc """
  Locks the named accounts, sorted by id, and returns them by identifier with
  `balance` read after the lock. A named account that does not exist is
  returned with a zero balance and no id; `move/4` opens nothing.
  """
  @spec lock([String.t()]) :: %{String.t() => %{id: String.t() | nil, balance: Decimal.t()}}
  def lock(identifiers) do
    identifiers = Enum.uniq(identifiers)

    # Internal: see the module doc.
    Account
    |> Ash.Query.filter(identifier in ^identifiers)
    |> Ash.Query.sort(:id)
    |> Ash.Query.for_read(:lock_accounts, %{}, authorize?: false)
    |> Ash.read!()

    identifiers |> Enum.zip(read(identifiers)) |> Map.new()
  end

  @doc "The balances of the named accounts, in order, read without locking."
  @spec balances([String.t()]) :: [Decimal.t()]
  def balances(identifiers), do: identifiers |> read() |> Enum.map(& &1.balance)

  defp read(identifiers) do
    # Internal: see the module doc.
    found =
      Account
      |> Ash.Query.filter(identifier in ^identifiers)
      |> Ash.Query.load(:current_balance)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.identifier, %{id: &1.id, balance: balance(&1.current_balance)}})

    Enum.map(identifiers, &Map.get(found, &1, %{id: nil, balance: Decimal.new(0)}))
  end

  @doc """
  Moves `amount` between two locked accounts and returns the accounts with
  both balances updated, and tells pages showing either person's balance. A
  zero amount moves nothing.
  """
  @spec move(map(), {String.t(), String.t()}, Decimal.t(), String.t()) :: map()
  def move(accounts, {from, to}, amount, operation) do
    if Decimal.eq?(amount, 0) do
      accounts
    else
      %{id: from_id} = Map.fetch!(accounts, from)
      %{id: to_id} = Map.fetch!(accounts, to)

      # Internal: see the module doc.
      Transfer
      |> Ash.Changeset.for_create(
        :transfer,
        %{
          amount: Amount.money(amount),
          from_account_id: from_id,
          to_account_id: to_id,
          operation: operation
        },
        authorize?: false
      )
      |> Ash.create!()

      Enum.each([from, to], &announce/1)

      accounts
      |> Map.update!(from, &%{&1 | balance: Decimal.sub(&1.balance, amount)})
      |> Map.update!(to, &%{&1 | balance: Decimal.add(&1.balance, amount)})
    end
  end

  @doc "A locked account's balance."
  @spec balance_of(map(), String.t()) :: Decimal.t()
  def balance_of(accounts, identifier),
    do: accounts |> Map.fetch!(identifier) |> Map.fetch!(:balance)

  defp announce(identifier) do
    case String.split(identifier, "/", parts: 2) do
      [kind, privy_user_id] when kind in @person_kinds ->
        RegentCredits.announce(privy_user_id)

      _regent_or_address ->
        :ok
    end
  end

  defp balance(nil), do: Decimal.new(0)
  defp balance(%Money{amount: amount}), do: amount
end

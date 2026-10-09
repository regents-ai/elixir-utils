defmodule RegentCredits.Gifts do
  @moduledoc """
  The work behind `RegentCredits.Gift`'s actions, in `RegentCredits.Ledger`'s
  order. The gift rows and transfers are written by the library after the
  action was authorized, so they run unauthorized.
  """

  require Ash.Query

  alias RegentChain.Address
  alias RegentCredits.{Amount, Gift, Ledger, Purchases, Wallets}
  alias RegentCredits.Errors.Refused

  @doc """
  Gives each recipient the amount once per `key`. A gift to a wallet an
  account holds goes straight to that account.
  """
  def give(%{key: key, to: to, amount: amount} = args, actor) do
    with :ok <- valid_amount(amount),
         {:ok, recipients} <- recipients(to) do
      owners = recipients |> Enum.map(&elem(&1, 1)) |> Wallets.owners()
      recipients |> Enum.flat_map(&accounts_of(&1, owners)) |> Ledger.open()
      from = Ledger.identifier(:regent_gifts, nil)
      accounts = Ledger.lock([from | Enum.map(recipients, &account(&1, owners))])
      given = given(key, Enum.map(recipients, &elem(&1, 1)))
      new = Enum.reject(recipients, fn {_kind, to} -> to in given end)

      Enum.each(new, fn recipient ->
        Ledger.move(accounts, {from, account(recipient, owners)}, amount, "gift:#{key}")
      end)

      # Internal: written by the authorized give action.
      Ash.bulk_create!(
        Enum.map(new, fn {_kind, to} ->
          %{key: key, to: to, amount: amount, note: args[:note], given_by: actor.privy_user_id}
        end),
        Gift,
        :record,
        authorize?: false
      )

      {:ok, read(key, Enum.map(recipients, &elem(&1, 1)))}
    end
  end

  @doc """
  Records that the account holds exactly these wallets, and moves everything
  waiting under them to the account: gifts to its given Credits, deposits
  to its purchased Credits along with the purchases themselves.
  """
  def attach_wallets(%{privy_user_id: owner, wallets: wallets}, _actor) do
    with {:ok, addresses} <- addresses(wallets) do
      Ledger.open(Ledger.person(owner))

      waiting =
        for {kind, into} <- [address_given: :given, address_purchased: :purchased],
            address <- addresses,
            do: {Ledger.identifier(kind, address), Ledger.identifier(into, owner)}

      accounts = Ledger.lock(Ledger.person(owner) ++ Enum.map(waiting, &elem(&1, 0)))
      Wallets.remember(owner, addresses)

      moved =
        waiting
        |> Enum.map(fn {account, to} -> {account, to, Ledger.balance_of(accounts, account)} end)
        |> Enum.filter(fn {_account, _to, balance} -> Decimal.gt?(balance, 0) end)

      Enum.each(moved, fn {account, to, balance} ->
        Ledger.move(accounts, {account, to}, balance, "attach:#{account}")
      end)

      Purchases.claim(owner, addresses)

      {:ok,
       Enum.reduce(moved, Decimal.new(0), fn {_account, _to, balance}, sum ->
         Decimal.add(sum, balance)
       end)}
    end
  end

  defp recipients(to) do
    recipients = to |> Enum.map(&recipient/1) |> Enum.uniq()

    if :error in recipients,
      do: {:error, Refused.exception(reason: :invalid_recipient)},
      else: {:ok, recipients}
  end

  defp recipient("did:privy:" <> _rest = privy_user_id), do: {:person, privy_user_id}

  defp recipient(value) do
    case Address.normalize(value) do
      {:ok, address} -> {:address, address}
      :error -> :error
    end
  end

  defp addresses(wallets) do
    normalized = Enum.map(wallets, &Address.normalize/1)

    if :error in normalized,
      do: {:error, Refused.exception(reason: :invalid_recipient)},
      else: {:ok, normalized |> Enum.map(&elem(&1, 1)) |> Enum.uniq()}
  end

  # A wallet an account holds stands for the account.
  defp holder({:address, address} = recipient, owners) do
    case Map.fetch(owners, address) do
      {:ok, privy_user_id} -> {:person, privy_user_id}
      :error -> recipient
    end
  end

  defp holder(recipient, _owners), do: recipient

  defp account(recipient, owners) do
    case holder(recipient, owners) do
      {:person, privy_user_id} -> Ledger.identifier(:given, privy_user_id)
      {:address, address} -> Ledger.identifier(:address_given, address)
    end
  end

  defp accounts_of(recipient, owners) do
    case holder(recipient, owners) do
      {:person, privy_user_id} -> Ledger.person(privy_user_id)
      {:address, _address} -> [account(recipient, owners)]
    end
  end

  defp given(key, to) do
    key |> read(to) |> MapSet.new(& &1.to)
  end

  defp read(key, to) do
    # Internal: read by the authorized give action.
    Gift
    |> Ash.Query.filter(key == ^key and to in ^to)
    |> Ash.read!(authorize?: false)
  end

  defp valid_amount(amount) do
    if Amount.valid?(amount), do: :ok, else: {:error, Refused.exception(reason: :invalid_amount)}
  end
end

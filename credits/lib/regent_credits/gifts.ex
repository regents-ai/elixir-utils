defmodule RegentCredits.Gifts do
  @moduledoc """
  The work behind `RegentCredits.Gift`'s actions, in `RegentCredits.Ledger`'s
  order. The gift rows and transfers are written by the library after the
  action was authorized, so they run unauthorized.
  """

  require Ash.Query

  alias RegentChain.Address
  alias RegentCredits.{Amount, Gift, Ledger}
  alias RegentCredits.Errors.Refused

  @doc "Gives each recipient the amount once per `key`."
  def give(%{key: key, to: to, amount: amount} = args, actor) do
    with :ok <- valid_amount(amount),
         {:ok, recipients} <- recipients(to) do
      recipients |> Enum.flat_map(&accounts_of/1) |> Ledger.open()
      from = Ledger.identifier(:regent_gifts, nil)
      accounts = Ledger.lock([from | Enum.map(recipients, &account/1)])
      given = given(key, Enum.map(recipients, &elem(&1, 1)))
      new = Enum.reject(recipients, fn {_kind, to} -> to in given end)

      Enum.each(new, fn recipient ->
        Ledger.move(accounts, {from, account(recipient)}, amount, "gift:#{key}")
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

  @doc "Moves everything waiting under the wallets to the account's given Credits."
  def attach_wallets(%{privy_user_id: owner, wallets: wallets}, _actor) do
    with {:ok, addresses} <- addresses(wallets) do
      Ledger.open(Ledger.person(owner))
      to = Ledger.identifier(:given, owner)
      waiting = Enum.map(addresses, &Ledger.identifier(:address_given, &1))
      accounts = Ledger.lock(Ledger.person(owner) ++ waiting)

      moved =
        waiting
        |> Enum.map(&{&1, Ledger.balance_of(accounts, &1)})
        |> Enum.filter(fn {_account, balance} -> Decimal.gt?(balance, 0) end)

      Enum.each(moved, fn {account, balance} ->
        Ledger.move(accounts, {account, to}, balance, "attach:#{account}")
      end)

      {:ok,
       Enum.reduce(moved, Decimal.new(0), fn {_account, balance}, sum ->
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

  defp account({:person, privy_user_id}), do: Ledger.identifier(:given, privy_user_id)
  defp account({:address, address}), do: Ledger.identifier(:address_given, address)

  defp accounts_of({:person, privy_user_id}), do: Ledger.person(privy_user_id)
  defp accounts_of({:address, _address} = recipient), do: [account(recipient)]

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

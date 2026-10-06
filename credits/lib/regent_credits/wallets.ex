defmodule RegentCredits.Wallets do
  @moduledoc """
  Which Privy account holds a wallet address, from `RegentCredits.Wallet`.
  Callers have authorized the operation itself, so these internal reads and
  writes run unauthorized.

  The owner is read before the operation's locks. A gift sent in the same
  moment its wallet is first attached can therefore still wait under the
  address; the account's next `attach_wallets` moves it, and nothing is lost.
  """

  require Ash.Query

  alias RegentCredits.Wallet

  @doc """
  Records that `owner` holds exactly these lowercase addresses: each one
  belongs to the account now, and a wallet the account no longer holds is
  forgotten. Runs after the account's accounts are locked, so two sign-ins
  of one account take turns.
  """
  @spec remember(String.t(), [String.t()]) :: :ok
  def remember(owner, addresses) do
    # Internal: written by the authorized attach action.
    Wallet
    |> Ash.Query.filter(privy_user_id == ^owner and address not in ^addresses)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    Ash.bulk_create!(
      Enum.map(addresses, &%{address: &1, privy_user_id: owner}),
      Wallet,
      :remember,
      authorize?: false
    )

    :ok
  end

  @doc "The Privy account holding each of these lowercase addresses that has one."
  @spec owners([String.t()]) :: %{String.t() => String.t()}
  def owners([]), do: %{}

  def owners(addresses) do
    # Internal: read by the authorized operation.
    Wallet
    |> Ash.Query.filter(address in ^addresses)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.address, &1.privy_user_id})
  end
end

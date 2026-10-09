defmodule RegentIdentity.SelectedWallet do
  @moduledoc """
  Profile edit checks: a display name of at most 320 bytes, and a selected
  wallet that is one of the person's verified linked wallets.
  """
  use Ash.Resource.Change
  @impl true
  def change(changeset, _opts, %{actor: %RegentPrivy.Session{} = actor}) do
    changeset =
      case Ash.Changeset.get_attribute(changeset, :display_name) do
        name when is_binary(name) and byte_size(name) > 320 ->
          Ash.Changeset.add_error(changeset, field: :display_name, message: "is too long")

        _ ->
          changeset
      end

    if Ash.Changeset.changing_attribute?(changeset, :wallet_address) do
      Ash.Changeset.before_action(changeset, &check_wallet(&1, actor))
    else
      changeset
    end
  end

  def change(changeset, _, _),
    do: Ash.Changeset.add_error(changeset, "verified identity required")

  defp check_wallet(locked, actor) do
    RegentIdentity.lock(actor)
    wallet = Ash.Changeset.get_attribute(locked, :wallet_address)

    with {:ok, current} when not is_nil(current) <-
           RegentIdentity.get_my_profile(actor: actor),
         true <-
           is_nil(wallet) or
             (wallet in actor.wallet_addresses and wallet in current.wallet_addresses) do
      locked
    else
      _ ->
        Ash.Changeset.add_error(locked,
          field: :wallet_address,
          message: "must be a verified linked wallet"
        )
    end
  end
end

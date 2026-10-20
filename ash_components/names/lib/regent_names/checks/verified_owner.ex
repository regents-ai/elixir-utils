defmodule RegentNames.Checks.VerifiedOwner do
  @moduledoc """
  The actor is a fresh Privy sign-in for the site's own app
  (`config :regent_names, privy_app_id: ...`) whose wallets are all well formed
  and lowercased.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "fresh paired Privy evidence for this application's wallet owner"

  @impl true
  def match?(%RegentPrivy.Session{app_id: app, wallet_addresses: wallets} = actor, _, _) do
    RegentIdentity.VerifiedActor.match?(actor, nil, []) and
      app == Application.fetch_env!(:regent_names, :privy_app_id) and
      is_list(wallets) and
      Enum.all?(wallets, &(is_binary(&1) and Regex.match?(~r/^0x[0-9a-f]{40}$/, &1)))
  end

  def match?(_, _, _), do: false
end

defmodule RegentPoints.Store do
  @moduledoc false
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, CapUsage, Entry, Event}
  @system %{role: :system}

  def system, do: @system

  def digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))
      |> Base.encode16(case: :lower)

  # Lock one canonical account for all of its awards and corrections. Cap rows
  # alone cannot serialize two different rules sharing one daily allowance.
  def lock_account(id) do
    Points.open_account!(%{id: id}, actor: @system)
    query = Account |> Ash.Query.filter(id == ^id) |> Ash.Query.lock(:for_update)
    Points.read_accounts!(query: query, actor: @system) |> List.first()
  end

  def event(id) do
    query = Ash.Query.filter(Event, id == ^id)
    Points.read_events!(query: query, actor: @system) |> List.first()
  end

  def entry(id) do
    Points.read_entries!(query: Ash.Query.filter(Entry, id == ^id), actor: @system)
    |> List.first()
  end

  def award(program, key) do
    query = Ash.Query.filter(Entry, program_id == ^program and award_key == ^key)
    Points.read_entries!(query: query, actor: @system) |> List.first()
  end

  def cap(account_id, program, scope, {start, stop}) do
    row =
      Points.reserve_cap!(
        %{
          account_id: account_id,
          program_id: program,
          cap_scope: scope,
          window_start: start,
          window_end: stop
        },
        actor: @system
      )

    query = CapUsage |> Ash.Query.filter(id == ^row.id) |> Ash.Query.lock(:for_update)
    Points.read_caps!(query: query, actor: @system) |> List.first()
  end

  def human(id) do
    RegentPoints.accounts().human(id)
  end

  def wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end

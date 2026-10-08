defmodule RegentPoints.Reverse do
  @moduledoc "Auditable partial corrections; earning allowances never reopen."
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Entry, Store}
  @impl true
  def run(%{arguments: args}, _, _) do
    case Store.entry(args.entry_id) do
      %{reversal_of_entry_id: nil, base_points_micro: base} = original when base > 0 ->
        Ash.transact(Account, fn ->
          Store.lock_account(original.account_id)
          correct(original, args)
        end)

      _ ->
        {:error, "Only a positive original award can be corrected"}
    end
  end

  defp correct(original, args) do
    key = "correction:" <> Store.digest({original.id, args.correction_key})

    case Store.award(original.program_id, key) do
      nil ->
        append(original, args, key)

      existing ->
        if existing.base_points_micro == -args.base_micro and existing.reason_code == args.reason,
          do: %{id: existing.id},
          else: {:error, "Correction key conflicts with its original amount or reason"}
    end
  end

  defp append(original, args, key) do
    query = Ash.Query.filter(Entry, reversal_of_entry_id == ^original.id)
    corrections = Points.read_entries!(query: query, actor: Store.system())
    reversed_base = -Enum.sum(Enum.map(corrections, & &1.base_points_micro))
    reversed_bonus = -Enum.sum(Enum.map(corrections, & &1.bonus_points_micro))

    if reversed_base + args.base_micro > original.base_points_micro do
      {:error, "Correction exceeds the original remaining award"}
    else
      # Cumulative rounding makes many partial corrections exactly equal one
      # full correction, including the last fractional micro-point of bonus.
      bonus =
        div((reversed_base + args.base_micro) * original.bonus_percent, 100) - reversed_bonus

      attrs =
        original
        |> Map.from_struct()
        |> Map.take([
          :program_id,
          :account_id,
          :event_id,
          :rule_id,
          :rule_version,
          :source_app,
          :actor_kind,
          :actor_id,
          :category,
          :milestone_key,
          :bonus_percent
        ])

      row =
        Points.append_entry!(
          Map.merge(attrs, %{
            award_key: key,
            base_points_micro: -args.base_micro,
            bonus_points_micro: -bonus,
            points_micro_delta: -args.base_micro - bonus,
            earned_at: original.earned_at,
            reversal_of_entry_id: original.id,
            reason_code: args.reason
          }),
          actor: Store.system()
        )

      %{id: row.id}
    end
  end
end

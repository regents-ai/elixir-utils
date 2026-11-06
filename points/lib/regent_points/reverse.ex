defmodule RegentPoints.Reverse do
  @moduledoc """
  Auditable partial corrections; a tallied period's bonus follows. Earning
  allowances never reopen, but a payment's dollar points taken back in full free
  the payment, so it can pay the right account. A partial take-back frees nothing.
  A spending award that used its payment and earned 0 is corrected by 0, which
  frees the payment the same way.
  """
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Entry, Store}
  @impl true
  def run(%{arguments: args}, _, _) do
    original = Store.entry(args.entry_id)

    if correctable?(original, args.points_micro) do
      Ash.transact(Account, fn ->
        Store.lock_account(original.account_id)
        correct(original, args)
      end)
    else
      {:error,
       "Only a positive original award, or a 0-point one that used its payment, can be corrected"}
    end
  end

  defp correctable?(%{reversal_of_entry_id: nil, points_micro_delta: points}, by) when points > 0,
    do: by > 0

  defp correctable?(%{reversal_of_entry_id: nil, points_micro_delta: 0} = original, 0),
    do: used_payment?(original)

  defp correctable?(_original, _by), do: false

  # A spending award used its payment unless it repeated one already used.
  defp used_payment?(entry),
    do: entry.category == "spending" and entry.reason_code != "allowance_used"

  defp correct(original, args) do
    key = "correction:" <> Store.digest({original.id, args.correction_key})

    case Store.award(original.program_id, key) do
      nil ->
        append(original, args, key)

      existing ->
        if existing.points_micro_delta == -args.points_micro and
             existing.reason_code == args.reason,
           do: %{id: existing.id},
           else: {:error, "Correction key conflicts with its original amount or reason"}
    end
  end

  defp append(original, args, key) do
    corrected =
      Entry
      |> Ash.Query.filter(reversal_of_entry_id == ^original.id)
      |> Ash.Query.for_read(:read, %{}, actor: Store.system())
      |> Ash.sum!(:points_micro_delta)

    reversed = -(corrected || 0)
    remaining = original.points_micro_delta - reversed

    # Nothing remains once an award is corrected in full, a 0-point one included.
    if args.points_micro > remaining or (corrected != nil and remaining == 0) do
      {:error, "Correction exceeds the original remaining award"}
    else
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
          :milestone_key
        ])

      row =
        Points.append_entry!(
          Map.merge(attrs, %{
            award_key: key,
            points_micro_delta: -args.points_micro,
            earned_at: original.earned_at,
            reversal_of_entry_id: original.id,
            reason_code: args.reason
          }),
          actor: Store.system()
        )

      Store.follow_period_bonus(row)

      if used_payment?(original) and args.points_micro == remaining do
        event = Store.event(original.event_id)
        payment = Store.payment(event.evidence, event.source_action_at)
        Points.release_cap!(payment, original.points_micro_delta, actor: Store.system())
      end

      %{id: row.id}
    end
  end
end

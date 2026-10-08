defmodule RegentPoints.IntakeWorker do
  @moduledoc "Verifies committed source facts and records Points work. Oban owns retries."
  use Oban.Worker, queue: :points, max_attempts: 10
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Rules, Store, Worker}

  @required ~w(source_app source_kind source_event_key account_id actor_kind actor_id source_action_at qualified_at evidence_ref evidence wallets)a

  @impl true
  def perform(%Oban.Job{args: input}) do
    id = input["rule_id"]

    with true <- Rules.enabled?(id),
         {:ok, facts} <- Rules.adapter(id).verify(input),
         :ok <- valid(facts, id),
         :ok <- same_source(input, facts),
         {:ok, rule} <- Rules.snapshot(id, facts.source_action_at),
         :ok <- eligible_source(rule, facts),
         {:ok, event} <- Ash.transact(Account, fn -> record(facts, rule) end) do
      case event do
        %{rejected: reason} -> reject(input, reason)
        _ -> :ok
      end
    else
      false -> reject(input, :rule_disabled)
      {:retry, reason} -> {:error, reason}
      {:error, reason} when is_atom(reason) -> reject(input, reason)
      {:error, reason} -> {:error, reason}
    end
  end

  defp same_source(input, facts) do
    if Enum.all?(
         [:source_app, :source_kind, :source_event_key],
         &(input[to_string(&1)] == facts[&1])
       ), do: :ok, else: {:error, :source_reference_mismatch}
  end

  defp eligible_source(%{"category" => "activity"}, facts) do
    if Rules.activity_app?(facts.source_app), do: :ok, else: {:error, :ineligible_activity_app}
  end

  defp eligible_source(_, _), do: :ok

  defp reject(input, reason) do
    # Rejections survive Oban pruning and never overwrite a previously accepted event.
    Points.reject_source!(
      %{
        source: input,
        reason_code: to_string(reason),
        rejection_key: Store.digest({input, reason})
      },
      actor: Store.system()
    )

    :ok
  end

  defp valid(facts, rule) when is_map(facts) do
    with true <- Enum.all?(@required, &Map.has_key?(facts, &1)),
         true <- is_map(facts.evidence),
         true <-
           Enum.all?(
             [:source_app, :source_kind, :source_event_key, :actor_id, :evidence_ref],
             &(is_binary(facts[&1]) and facts[&1] != "")
           ),
         :ok <- identity(facts),
         :ok <- time(facts),
         :ok <- proof(facts, rule),
         :ok <- solution_parties(facts, rule),
         true <- is_list(facts.wallets),
         true <- Enum.all?(facts.wallets, &wallet?/1) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :incomplete_source_evidence}
    end
  end

  defp valid(_, _), do: {:error, :invalid_source_evidence}

  defp identity(facts) do
    if facts.actor_kind in ["human", "agent"] and is_integer(facts.account_id) and
         facts.account_id > 0, do: :ok, else: {:error, :invalid_attribution}
  end

  defp time(%{source_action_at: %DateTime{} = action, qualified_at: %DateTime{} = qualified}) do
    if DateTime.compare(qualified, action) != :lt and
         DateTime.compare(qualified, DateTime.utc_now()) != :gt,
       do: :ok,
       else: {:error, :invalid_qualification_time}
  end

  defp time(_), do: {:error, :invalid_source_time}

  defp proof(facts, rule) do
    needed = if facts.actor_kind == "agent", do: ["attribution_link_id"], else: []

    needed =
      if String.starts_with?(rule, "keyfleet."),
        do: needed ++ ["key_id", "ownership_epoch"],
        else: needed

    needed =
      if String.starts_with?(rule, "social.") or rule == "agent.erc8004_registered",
        do: ["subject_key" | needed],
        else: needed

    if Enum.all?(needed, &(is_binary(facts.evidence[&1]) and facts.evidence[&1] != "")),
      do: :ok,
      else: {:error, :missing_attribution_or_subject_proof}
  end

  # The source adapter resolves both parties to canonical humans, including any
  # linked wallets and connected agents. A different signer is not independence.
  defp solution_parties(facts, rule)
       when rule in [
              "patchbay.solution_accepted",
              "patchbay.first_solution",
              "patchbay.report_resolved",
              "patchbay.first_resolved_priority_report"
            ] do
    asker = facts.evidence["asker_account_id"]
    solver = facts.evidence["solver_account_id"]

    beneficiary =
      if rule in ["patchbay.solution_accepted", "patchbay.first_solution"],
        do: solver,
        else: asker

    cond do
      not (is_integer(asker) and asker > 0 and is_integer(solver) and solver > 0) ->
        {:error, :missing_solution_parties}

      asker == solver ->
        {:error, :self_acceptance}

      facts.account_id != beneficiary ->
        {:error, :solution_beneficiary_mismatch}

      true ->
        :ok
    end
  end

  defp solution_parties(_, _), do: :ok

  defp wallet?(wallet), do: is_binary(wallet) and Regex.match?(~r/^0x[0-9a-f]{40}$/, wallet)

  defp record(facts, rule) do
    Store.lock_account(facts.account_id)
    # Business identity excludes transport, beneficiary and rule version. A WebMCP
    # retry or reassignment cannot invent a second award for the same operation.
    key = Store.digest({facts.source_app, facts.source_kind, facts.source_event_key, rule["id"]})

    # The digest covers exactly the stored facts, so an adapter's extra keys can
    # never make the same source look like a conflicting one.
    stored = facts |> Map.take(@required) |> Map.update!(:wallets, &Enum.uniq/1)

    attrs =
      Map.merge(stored, %{
        program_id: Rules.program(),
        rule_id: rule["id"],
        rule_snapshot: rule,
        award_key: key,
        payload_digest: Store.digest(stored)
      })

    event = Points.create_event!(attrs, actor: Store.system())

    if event.payload_digest == attrs.payload_digest do
      %{event_id: event.id} |> Worker.new() |> Oban.insert!()
      %{id: event.id, status: event.processing_status}
    else
      %{rejected: :source_identity_conflict}
    end
  end
end

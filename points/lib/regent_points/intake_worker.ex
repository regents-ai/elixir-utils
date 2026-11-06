defmodule RegentPoints.IntakeWorker do
  @moduledoc "Verifies committed source facts and records Points work. Oban owns retries."
  use Oban.Worker, queue: :points, max_attempts: 10
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Event, Rules, Store, Worker}

  # A payment worth more than a billion dollars is not a purchase on a Regent site.
  @most_usd_micros 1_000_000_000_000_000

  @required ~w(source_app source_kind source_event_key account_id actor_kind actor_id source_action_at qualified_at evidence_ref evidence)a

  @impl true
  def perform(%Oban.Job{args: input}) do
    id = input["rule_id"]

    with true <- Rules.enabled?(id),
         {:ok, facts} <- Rules.adapter(id).verify(input),
         :ok <- valid(facts, id),
         :ok <- same_source(input, facts),
         facts = at_start(id, facts),
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

  # What an account already had before the start earns at the start
  # (RegentPoints.StartAwards); every other rule earns only for what happens after it.
  defp at_start(id, facts) do
    start = Keyword.get(Rules.config(), :starts_at)

    if Rules.start_rule?(id) and start != nil and
         DateTime.before?(facts.source_action_at, start),
       do: %{
         facts
         | source_action_at: start,
           qualified_at: Enum.max([facts.qualified_at, start], DateTime)
       },
       else: facts
  end

  defp eligible_source(%{"category" => "activity"}, facts) do
    if Rules.activity_app?(facts.source_app), do: :ok, else: {:error, :ineligible_activity_app}
  end

  # A spending rule is reported only by its own site, and names the one payment it
  # is for and the dollars it proves.
  defp eligible_source(%{"category" => "spending", "id" => id}, facts) do
    cond do
      facts.source_app != hd(String.split(id, ".")) ->
        {:error, :ineligible_spending_app}

      not paid?(facts.evidence) ->
        {:error, :invalid_spending_evidence}

      facts.evidence["usd_micros"] > @most_usd_micros ->
        {:error, :spending_amount_too_large}

      facts.evidence["usd_micros"] != dollars(facts.evidence) ->
        {:error, :invalid_spending_evidence}

      true ->
        :ok
    end
  end

  defp eligible_source(_, _), do: :ok

  defp paid?(%{
         "usd_micros" => usd,
         "payer" => payer,
         "token" => token,
         "token_amount" => amount,
         "token_decimals" => decimals,
         "price_usd" => price,
         "price_source" => source,
         "chain_id" => chain,
         "block_number" => block,
         "tx_hash" => tx,
         "log_index" => log
       }) do
    is_integer(usd) and usd > 0 and text?(payer, ~r/\A0x[0-9a-f]{40}\z/) and
      text?(token, ~r/\A0x[0-9a-f]{40}\z/) and text?(amount, ~r/\A[1-9][0-9]{0,77}\z/) and
      is_integer(decimals) and decimals in 0..255 and
      text?(price, ~r/\A(0|[1-9][0-9]*)(\.[0-9]+)?\z/) and price =~ ~r/[1-9]/ and
      text?(source, ~r/\S/) and is_integer(chain) and chain > 0 and is_integer(block) and
      block > 0 and text?(tx, ~r/\A0x[0-9a-f]{64}\z/) and is_integer(log) and log >= 0
  end

  defp paid?(_evidence), do: false

  # The payment's dollars in millionths, rounded down:
  # token_amount × price_usd × 10^6 / 10^token_decimals. Whole numbers keep every
  # digit; Decimal's default 28 would round a 78-digit token amount.
  defp dollars(%{"token_amount" => amount, "price_usd" => price, "token_decimals" => decimals}) do
    {digits, places} =
      case String.split(price, ".") do
        [whole] -> {whole, 0}
        [whole, fraction] -> {whole <> fraction, byte_size(fraction)}
      end

    div(
      String.to_integer(amount) * String.to_integer(digits) * 1_000_000,
      10 ** (places + decimals)
    )
  end

  defp text?(value, pattern), do: is_binary(value) and value =~ pattern

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
         :ok <- proof(facts, rule) do
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
      if String.starts_with?(rule, "social."),
        do: ["subject_key" | needed],
        else: needed

    if Enum.all?(needed, &(is_binary(facts.evidence[&1]) and facts.evidence[&1] != "")),
      do: :ok,
      else: {:error, :missing_attribution_or_subject_proof}
  end

  defp record(facts, rule) do
    Store.lock_account(facts.account_id)
    # Business identity excludes transport, beneficiary and rule version. A WebMCP
    # retry or reassignment cannot invent a second award for the same operation.
    key = Store.digest({facts.source_app, facts.source_kind, facts.source_event_key, rule["id"]})

    # The digest covers exactly the stored facts, so an adapter's extra keys can
    # never make the same source look like a conflicting one.
    stored = Map.take(facts, @required)

    attrs =
      Map.merge(stored, %{
        program_id: Rules.program(),
        rule_id: rule["id"],
        rule_snapshot: rule,
        award_key: key,
        payload_digest: Store.digest(stored)
      })

    if earned?(facts.account_id, rule) do
      %{status: :earned}
    else
      event = Points.create_event!(attrs, actor: Store.system())

      if event.payload_digest == attrs.payload_digest do
        %{event_id: event.id} |> Worker.new() |> Oban.insert!()
        %{id: event.id, status: event.processing_status}
      else
        %{rejected: :source_identity_conflict}
      end
    end
  end

  # Under the account's lock: a one-time award the account has already earned,
  # or one already on its way, records nothing more and queues no award.
  defp earned?(account_id, %{"category" => "milestone", "id" => id}) do
    Event
    |> Ash.Query.filter(
      account_id == ^account_id and rule_id == ^id and
        processing_status in [:pending, :confirmed]
    )
    |> Ash.Query.for_read(:read, %{}, actor: Store.system())
    |> Ash.exists?()
  end

  defp earned?(_account_id, _rule), do: false
end

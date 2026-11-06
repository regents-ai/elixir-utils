Code.require_file("helpers.exs", __DIR__)

defmodule Review3.FindingsTest do
  # The third review's findings and notes (abbc9e04). The tests of findings 2 to 4
  # keep the review's setup and hold the fix; finding 5 and the notes prove what
  # stays as it is. (Finding 1, the collision, needs real connections:
  # test/review3/races_test.exs.)
  use ExUnit.Case, async: false
  import Review3.Helpers
  alias RegentPoints.{IntakeWorker, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    on_exit(configure())
    :ok
  end

  defp reverse(id, key, points, reason \\ "wrong_account"),
    do: RegentPoints.reverse(id, key, points, reason, actor: system())

  # Runs the intake job itself, the way Oban does, and answers what the job answered.
  defp intake(rule, account, at, evidence, opts \\ []) do
    facts = facts(rule, account, at, evidence, opts)
    Review3.Source.put(facts.source_event_key, facts)

    answer =
      try do
        IntakeWorker.perform(%Oban.Job{
          args: %{
            "rule_id" => rule,
            "source_app" => facts.source_app,
            "source_kind" => facts.source_kind,
            "source_event_key" => facts.source_event_key
          }
        })
      rescue
        error -> {:raised, error}
      end

    {facts.source_event_key, answer}
  end

  defp raw_correction(original, delta, category, key) do
    Repo.query(
      """
      INSERT INTO regent_points.point_entries
        (program_id, account_id, event_id, award_key, rule_id, rule_version, source_app, actor_kind,
         actor_id, category, points_micro_delta, earned_at, reversal_of_entry_id, reason_code)
      SELECT program_id, account_id, event_id, $2, rule_id, rule_version, source_app, actor_kind,
         actor_id, $3, $4, earned_at, id, 'raw'
      FROM regent_points.point_entries WHERE id = $1
      """,
      [Ecto.UUID.dump!(original.id), key, category, delta],
      mode: :savepoint
    )
  end

  test "PROOF finding 2: a price source the database cannot store is refused once, as invalid evidence, and the refusal keeps only the report's reference" do
    for bad <- ["face\0value", <<255, 65>>] do
      account = person()
      evidence = payment(5_000_000, %{"price_source" => bad})
      {key, answer} = intake("patchbay.payment_spend", account, midnight(), evidence)

      # Answered at once: a refusal, never an error Oban runs again.
      assert answer == :ok
      assert events(key) == []
      assert rejections(key) == ["invalid_spending_evidence"]
      assert payment_row(evidence) == nil
      assert total(account) == 0

      [refusal] =
        for rejection <- RegentPoints.read_rejections!(actor: system()),
            rejection.source["source_event_key"] == key,
            do: rejection

      assert Map.keys(refusal.source) |> Enum.sort() ==
               ~w(rule_id source_app source_event_key source_kind)

      # The same payment with a storable price source is fine.
      assert {_key, :ok} =
               intake("patchbay.payment_spend", account, midnight(), %{
                 evidence
                 | "price_source" => "face_value"
               })
    end

    # And three million characters are refused.
    evidence = payment(5_000_000, %{"price_source" => String.duplicate("x", 3_000_000)})
    assert outcome(evidence) == {nil, ["invalid_spending_evidence"]}
  end

  test "PROOF finding 3: a payment first reported under a long (allowed) source id is reported again after its take-back and pays the right account" do
    [wrong, right] = [person(), person()]
    key = String.duplicate("k", 500)
    evidence = payment(40_000_000)

    assert earned(pay("patchbay.payment_spend", wrong, midnight(), evidence, key: key)) ==
             40_000_000

    assert {:ok, _} = reverse(entry(key).id, "moved-to-right-account", 40_000_000)
    assert payment_row(evidence) == {0, 0}

    again = RegentPoints.source_after_take_back(key, "moved-to-right-account")
    assert byte_size(again) == 70

    {^again, {:ok, _}} = report("patchbay.payment_spend", right, midnight(), evidence, key: again)
    assert earned(again) == 40_000_000
    assert total(right) == 40_000_000
    assert total(wrong) == 0
    assert payment_row(evidence) == {1, 40_000_000}
  end

  test "PROOF finding 4: pinned-note spending is reported as 'template' by every site, and two sites' note 42 are two sources that both pay" do
    [first, second] = [person(), person()]

    # Site one reports its pinned note 42. Site two reports its own pinned note 42:
    # another person, another payment.
    assert earned(
             pay("template.pinned_note_spend", first, midnight(), payment(10_000_000),
               key: RegentPoints.pinned_note_source("regents", "42"),
               kind: "pinned_note"
             )
           ) == 10_000_000

    other = payment(25_000_000)

    {key, {:ok, _}} =
      report("template.pinned_note_spend", second, midnight(), other,
        key: RegentPoints.pinned_note_source("patchbay", "42"),
        kind: "pinned_note"
      )

    assert rejections(key) == []
    assert earned(key) == 25_000_000
    assert total(second) == 25_000_000
    assert payment_row(other) == {1, 25_000_000}

    # No site can report it under its own name.
    for app <- ~w(patchbay keyfleet autolaunch regents techtree) do
      {own, {:ok, _}} = report("template.pinned_note_spend", second, midnight(), other, app: app)
      assert rejections(own) == ["ineligible_spending_app"]
    end
  end

  test "PROOF note (question 6): which site name may report which rule" do
    account = person()

    # Spending: only the name in the rule's id, exactly.
    for {rule, app} <- [
          {"keyfleet.key_spend", "patchbay"},
          {"patchbay.payment_spend", "autolaunch"},
          {"autolaunch.auction_bid_spend", "Autolaunch"},
          {"keyfleet.key_spend", "keyfleet "},
          {"patchbay.payment_spend", "template"}
        ] do
      {key, {:ok, _}} = report(rule, account, midnight(), payment(5_000_000), app: app)
      assert rejections(key) == ["ineligible_spending_app"]
      assert earned(key) == nil
    end

    # Actions: any of the sites with daily actions may report another site's rule.
    {key, {:ok, _}} =
      report("patchbay.reply_published", account, midnight(), %{}, app: "keyfleet")

    assert earned(key) > 0
    {key, {:ok, _}} = report("keyfleet.key_bought", account, midnight(), %{}, app: "autolaunch")
    assert earned(key) > 0

    {key, {:ok, _}} =
      report("patchbay.reply_published", account, midnight(), %{}, app: "template")

    assert rejections(key) == ["ineligible_activity_app"]

    # One-time awards: any name at all.
    {key, {:ok, _}} =
      report("keyfleet.first_message", account, midnight(), %{}, app: "anything-at-all")

    assert earned(key) > 0

    # The name is only what the reporting site's own adapter says: nothing ties it to
    # the site that is running. This "site" is none of the four and reports all four.
    for rule <- spending() do
      assert earned(pay(rule, person(), midnight(), 5_000_000)) == 5_000_000
    end
  end

  test "PROOF note: the 100 dollars a day is counted per program id; a host set to another program id gives the same account 100 more on the same day" do
    account = person()
    assert earned(pay("keyfleet.key_spend", account, midnight(), limit())) == limit()
    assert earned(pay("patchbay.payment_spend", account, midnight(), 1_000_000)) == 0

    restore = configure("review3-second-program")
    assert earned(pay("patchbay.payment_spend", account, midnight(), limit())) == limit()
    restore.()

    %{rows: [[sum]]} =
      Repo.query!(
        "SELECT sum(points_micro_delta)::bigint FROM regent_points.point_entries WHERE account_id = $1 AND category = 'spending'",
        [account]
      )

    assert sum == 2 * limit()
  end

  test "PROOF finding 5: with plain SQL the database lets a 0 correction be written for an action's award, and for awards that never used a payment, if the correction row calls itself 'spending'" do
    account = person()
    {key, {:ok, _}} = report("patchbay.reply_published", account, midnight(), %{})
    action = entry(key)
    assert action.category == "activity"

    # The README: the database "lets a correction be 0 only for a spending award".
    assert {:ok, %{num_rows: 1}} = raw_correction(action, 0, "spending", "raw-a")

    # A positive spending award (the library refuses a 0 correction of it).
    evidence = payment(10_000_000)
    paid = entry(pay("keyfleet.key_spend", account, midnight(), evidence))
    assert {:error, _} = reverse(paid.id, "zero", 0)
    assert {:ok, %{num_rows: 1}} = raw_correction(paid, 0, "spending", "raw-b")

    # A repeat that never used the payment (the library refuses it too).
    repeat = entry(pay("patchbay.payment_spend", person(), midnight(), evidence))
    assert repeat.reason_code == "allowance_used"
    assert {:error, _} = reverse(repeat.id, "zero", 0)
    assert {:ok, %{num_rows: 1}} = raw_correction(repeat, 0, "spending", "raw-c")

    # Not claimed by the docs, noted: nothing in the database stops corrections
    # larger than the award (the library's own check is the only one).
    assert {:ok, %{num_rows: 1}} = raw_correction(paid, -25_000_000, "spending", "raw-d")
    assert total(account) < 0
  end
end

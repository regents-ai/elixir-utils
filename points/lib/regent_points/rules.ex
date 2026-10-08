defmodule RegentPoints.Rules do
  @moduledoc """
  Finite proposed catalog. Nothing earns until the founder approves a rule,
  its source adapter is installed, and the program has an explicit start time.
  Rates are pinned on intake; retries never apply today's pricing to old work.
  """
  @unit 1_000_000
  @milestones [
    {"account.email_verified", 5},
    {"regents.first_stake", 10},
    {"regents.first_reward_claim", 10},
    {"regents.first_redemption", 10},
    {"account.activated", 25},
    {"account.profile_completed", 10},
    {"social.x", 10},
    {"social.github", 10},
    {"social.farcaster", 10},
    {"identity.ens_selected", 25},
    {"agent.paired", 10},
    {"agent.activated", 25},
    {"agent.erc8004_registered", 25},
    {"app.first_use.regents", 10},
    {"app.first_use.patchbay", 10},
    {"app.first_use.techtree", 10},
    {"app.first_use.autolaunch", 10},
    {"app.first_use.keyfleet", 10},
    {"patchbay.first_report", 10},
    {"patchbay.first_reply", 10},
    {"patchbay.first_solution", 25},
    {"patchbay.first_paid_assist", 10},
    {"patchbay.first_resolved_priority_report", 15},
    {"techtree.first_signing_key", 10},
    {"techtree.first_non_demo_result", 25},
    {"autolaunch.first_launch", 20},
    {"autolaunch.first_graduation", 50},
    {"autolaunch.first_settled_auction", 10},
    {"keyfleet.first_membership", 10},
    {"keyfleet.first_reveal", 5},
    {"keyfleet.first_authorized_agent", 10},
    {"keyfleet.first_message", 5},
    {"keyfleet.first_vote", 10},
    {"keyfleet.integration.marimo", 10},
    {"keyfleet.integration.ddocs", 10},
    {"keyfleet.integration.twigpine", 10},
    {"keyfleet.integration.activegraph", 10}
  ]
  @activity [
    {"keyfleet.rollcall", 5, 1, "day"},
    {"patchbay.report_published", 10, 1, "day"},
    {"patchbay.reply_published", 5, 2, "day"},
    {"patchbay.solution_accepted", 20, 1, "day"},
    {"patchbay.report_resolved", 5, 1, "day"},
    {"patchbay.repair_verified", 15, 2, "day"}
  ]

  @labels %{
    "credits.purchase_settled" => "Credits purchase",
    "keyfleet.rollcall" => "Rollcall completed",
    "patchbay.report_published" => "Report published",
    "patchbay.reply_published" => "Reply published",
    "patchbay.solution_accepted" => "Solution accepted",
    "patchbay.report_resolved" => "Report resolved",
    "patchbay.repair_verified" => "Repair independently verified",
    "identity.ens_selected" => "Verified ENS name selected",
    "agent.erc8004_registered" => "First ERC-8004 registration"
  }

  def label(id) do
    Map.get_lazy(@labels, id, fn ->
      id |> String.split(".") |> List.last() |> String.replace("_", " ") |> String.capitalize()
    end)
  end

  def catalog do
    milestones =
      Enum.map(@milestones, fn {id, points} ->
        rule(id, "milestone", points, 1, "lifetime")
      end)

    activity =
      Enum.map(@activity, fn {id, points, count, period} ->
        rule(id, "activity", points, count, period)
      end)

    [rule("credits.purchase_settled", "credits", nil, nil, "day") | milestones ++ activity]
  end

  def config, do: Application.get_all_env(:regent_points)
  def unit, do: @unit
  def program, do: Keyword.fetch!(config(), :program_id)
  def milestone_total, do: Enum.sum(Enum.map(@milestones, &elem(&1, 1)))
  def enabled?(id), do: id in Keyword.get(config(), :approved_rules, []) and adapter(id) != nil
  def adapter(id), do: config() |> Keyword.get(:adapters, %{}) |> Map.get(id)

  def snapshot(id, at) do
    with %DateTime{} = start <- Keyword.get(config(), :starts_at),
         true <- DateTime.compare(at, start) != :lt,
         true <- DateTime.compare(at, DateTime.utc_now()) != :gt,
         true <- enabled?(id),
         %{} = rule <- Enum.find(catalog(), &(&1["id"] == id)) do
      {:ok, Map.put(rule, "effective_at", DateTime.to_iso8601(start))}
    else
      _ -> {:error, :rule_not_active}
    end
  end

  def base_micro(%{"category" => "credits", "micro_points_per_atomic_usdc" => rate}, evidence)
      when is_integer(rate) and rate > 0 do
    # Purchased, non-promotional Credits only. A source adapter must prove the
    # settled purchase and funding provenance; a client amount is never evidence.
    case evidence["purchased_usdc_atomic"] do
      n when is_integer(n) and n > 0 -> {:ok, n * rate}
      _ -> {:error, :invalid_purchase_amount}
    end
  end

  def base_micro(%{"points" => points}, _evidence) when is_integer(points),
    do: {:ok, points * @unit}

  def base_micro(_, _), do: {:error, :invalid_rule_snapshot}

  def allowance_scope(%{"category" => "credits"}, _actor), do: "credits"
  def allowance_scope(%{"category" => "activity"}, actor), do: "activity:#{actor}"
  def allowance_scope(_, _), do: nil

  def window("lifetime", _at), do: {~D[1970-01-01], nil}

  def window("day", at) do
    day = at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()
    {day, Date.add(day, 1)}
  end

  def daily_cap("activity:human"), do: 50 * @unit
  def daily_cap(scope) when scope in ["credits", "activity:agent"], do: 100 * @unit
  def activity_app?(app), do: app in ["patchbay", "keyfleet", "autolaunch"]

  defp rule(id, category, points, count, period),
    do: %{
      "id" => id,
      "version" => 1,
      "category" => category,
      "points" => points,
      "count" => count,
      "period" => period,
      "daily_caps_micro" =>
        Map.new(["credits", "activity:human", "activity:agent"], &{&1, daily_cap(&1)}),
      "micro_points_per_atomic_usdc" => if(category == "credits", do: 10),
      "milestone_key" => if(category == "milestone", do: id)
    }
end

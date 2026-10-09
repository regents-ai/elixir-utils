defmodule RegentPoints.Rules do
  @moduledoc """
  Finite proposed catalog. Nothing earns until the founder approves a rule,
  its source adapter is installed, and the program has an explicit start time.
  Rates are pinned on intake; retries never apply today's pricing to old work.
  """
  @unit 1_000_000
  @milestones [
    {"account.email_verified", 5, "Email verified"},
    {"regents.first_stake", 10, "First stake on Regents"},
    {"regents.first_reward_claim", 10, "First staking reward claimed"},
    {"regents.first_redemption", 10, "First redemption on Regents"},
    {"account.activated", 25, "Account activated"},
    {"account.profile_completed", 10, "Profile completed"},
    {"social.x", 10, "X account linked"},
    {"social.github", 10, "GitHub account linked"},
    {"social.farcaster", 10, "Farcaster account linked"},
    {"identity.ens_selected", 25, "Verified ENS name chosen"},
    {"agent.paired", 10, "First agent connected"},
    {"agent.activated", 25, "First agent activated"},
    {"agent.erc8004_registered", 25, "First agent listed on ERC-8004"},
    {"app.first_use.regents", 10, "First use of Regents"},
    {"app.first_use.patchbay", 10, "First use of Patchbay"},
    {"app.first_use.techtree", 10, "First use of Techtree"},
    {"app.first_use.autolaunch", 10, "First use of Autolaunch"},
    {"app.first_use.keyfleet", 10, "First use of Keyfleet"},
    {"patchbay.first_report", 10, "First Patchbay report"},
    {"patchbay.first_reply", 10, "First Patchbay reply"},
    {"patchbay.first_solution", 25, "First Patchbay solution"},
    {"patchbay.first_paid_assist", 10, "First paid Patchbay assist"},
    {"patchbay.first_resolved_priority_report", 15, "First priority Patchbay report resolved"},
    {"techtree.first_signing_key", 10, "First Techtree signing key"},
    {"techtree.first_non_demo_result", 25, "First Techtree result"},
    {"autolaunch.first_launch", 20, "First Autolaunch launch"},
    {"autolaunch.first_graduation", 50, "First Autolaunch graduation"},
    {"autolaunch.first_settled_auction", 10, "First Autolaunch auction settled"},
    {"keyfleet.first_membership", 10, "First Keyfleet membership"},
    {"keyfleet.first_reveal", 5, "First Keyfleet key revealed"},
    {"keyfleet.first_authorized_agent", 10, "First agent authorized on Keyfleet"},
    {"keyfleet.first_message", 5, "First Keyfleet message"},
    {"keyfleet.first_vote", 10, "First Keyfleet vote"},
    {"keyfleet.integration.marimo", 10, "Marimo used with Keyfleet"},
    {"keyfleet.integration.ddocs", 10, "dDocs used with Keyfleet"},
    {"keyfleet.integration.twigpine", 10, "Twigpine used with Keyfleet"},
    {"keyfleet.integration.activegraph", 10, "ActiveGraph used with Keyfleet"},
    {"template.first_agent_note", 10, "First note written by your agent"}
  ]
  @activity [
    {"patchbay.report_published", 10, 1, "day", "Patchbay report published"},
    {"patchbay.reply_published", 5, 2, "day", "Patchbay reply published"},
    {"patchbay.solution_accepted", 20, 1, "day", "Patchbay solution accepted"},
    {"patchbay.report_resolved", 5, 1, "day", "Patchbay report resolved"}
  ]

  @credits {"credits.purchase_settled", "Credits bought"}
  @labels Map.new(
            [@credits] ++
              for({id, _points, label} <- @milestones, do: {id, label}) ++
              for({id, _points, _count, _period, label} <- @activity, do: {id, label})
          )

  @doc "The customer name of every catalog rule, including the source app."
  def label(id), do: Map.fetch!(@labels, id)

  def catalog(at \\ DateTime.utc_now()) do
    milestones =
      Enum.map(@milestones, fn {id, points, _label} ->
        rule(id, "milestone", points, 1, "lifetime")
      end)

    activity =
      Enum.map(@activity, fn {id, points, count, period, _label} ->
        rule(id, "activity", points, count, period)
      end)

    {credits, _label} = @credits

    [rule(credits, "credits", nil, nil, "day") | milestones ++ activity]
    |> Enum.map(&version(&1, at))
  end

  def config, do: Application.get_all_env(:regent_points)
  def unit, do: @unit
  def program, do: Keyword.fetch!(config(), :program_id)
  def milestone_total, do: Enum.sum(Enum.map(@milestones, &elem(&1, 1)))
  def enabled?(id), do: id in Keyword.get(config(), :approved_rules, []) and adapter(id) != nil
  def adapter(id), do: config() |> Keyword.get(:adapters, %{}) |> Map.get(id)

  @doc "The catalog rules this site has a source for: the rules its Points page lists."
  def tracked, do: Enum.filter(catalog(), &adapter(&1["id"]))

  @doc "The catalog rules that earn right now."
  def active,
    do: Enum.filter(catalog(), &match?({:ok, _}, snapshot(&1["id"], DateTime.utc_now())))

  def snapshot(id, at) do
    with %DateTime{} = start <- Keyword.get(config(), :starts_at),
         true <- DateTime.compare(at, start) != :lt,
         true <- DateTime.compare(at, DateTime.utc_now()) != :gt,
         true <- enabled?(id),
         %{} = rule <- Enum.find(catalog(at), &(&1["id"] == id)) do
      {:ok, Map.put(rule, "effective_at", DateTime.to_iso8601(effective_at(rule, start)))}
    else
      _ -> {:error, :rule_not_active}
    end
  end

  @doc "Program period `n` as `{start, stop}`: 30-day periods counted from the start time."
  def period(n) do
    start = Keyword.fetch!(config(), :starts_at)
    {DateTime.add(start, (n - 1) * 30, :day), DateTime.add(start, n * 30, :day)}
  end

  @doc "The program period `at` falls in. Every award is earned at or after the start."
  def period_of(at) do
    start = Keyword.fetch!(config(), :starts_at)
    div(DateTime.diff(at, start, :second), 30 * 86_400) + 1
  end

  @doc "The program periods that have ended by `now`, oldest first. Each gets one bonus tally."
  def ended_periods(now) do
    case Keyword.get(config(), :starts_at) do
      %DateTime{} ->
        1
        |> Stream.iterate(&(&1 + 1))
        |> Enum.take_while(&(DateTime.compare(elem(period(&1), 1), now) != :gt))

      nil ->
        []
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
  def allowance_scope(%{"category" => "activity", "version" => 2}, _actor), do: "activity:account"
  def allowance_scope(%{"category" => "activity"}, actor), do: "activity:#{actor}"
  def allowance_scope(_, _), do: nil

  def window("lifetime", _at), do: {~D[1970-01-01], nil}

  def window("day", at) do
    day = at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()
    {day, Date.add(day, 1)}
  end

  def daily_cap("activity:human"), do: 50 * @unit

  def daily_cap(scope) when scope in ["credits", "activity:agent", "activity:account"],
    do: 100 * @unit

  @doc "The apps the daily rules among `rules` come from."
  def daily_apps(rules) do
    for %{"category" => "activity", "id" => id} <- rules,
        uniq: true,
        do: hd(String.split(id, "."))
  end

  def activity_app?(app), do: app in daily_apps(catalog())

  @doc "Shared per-action allowance for v2; historical v1 keeps its original actor pools."
  def count_scope(%{"category" => "activity", "version" => 1, "id" => id}, actor),
    do: id <> ":" <> actor

  def count_scope(rule, _actor), do: rule["milestone_key"] || rule["id"]

  defp version(rule, at) do
    case cutover() do
      nil ->
        rule

      cutover ->
        if DateTime.compare(at, cutover) == :lt do
          rule
        else
          %{
            rule
            | "version" => 2,
              "daily_caps_micro" => Map.new(["credits", "activity:account"], &{&1, daily_cap(&1)})
          }
        end
    end
  end

  defp effective_at(%{"version" => 2}, _start), do: cutover()
  defp effective_at(_rule, start), do: start

  # Explicit configuration does not enable any program or approved rule. All
  # services must deploy compatible code before setting the same UTC midnight.
  defp cutover do
    case Keyword.get(config(), :unified_activity_starts_at) do
      nil ->
        nil

      %DateTime{time_zone: "Etc/UTC", hour: 0, minute: 0, second: 0, microsecond: {0, _}} = at ->
        case Keyword.get(config(), :starts_at) do
          %DateTime{} = start ->
            if DateTime.compare(at, start) == :lt,
              do: raise(ArgumentError, "unified activity cannot precede the program start")

          _ ->
            :ok
        end

        at

      _ ->
        raise ArgumentError, "unified_activity_starts_at must be a UTC midnight"
    end
  end

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

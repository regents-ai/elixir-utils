defmodule RegentPoints.Rules do
  @moduledoc """
  Finite proposed catalog. Nothing earns until the founder approves a rule,
  its source adapter is installed, and the program has an explicit start time.
  Rates are pinned on intake; retries never apply today's pricing to old work.

  A rule's id never changes. A changed rule keeps its id and gets the next
  version, so what an account earned under the old version still counts
  against the new one; a new id is only for a new action.
  """
  @unit 1_000_000
  @milestones [
    {"account.activated", 1, 25, "Account activated"},
    {"social.x", 1, 10, "X account linked"},
    {"social.github", 1, 10, "GitHub account linked"},
    {"social.farcaster", 1, 10, "Farcaster account linked"},
    {"agent.activated", 1, 25, "First paired agent"},
    {"autolaunch.first_graduation", 1, 50, "First Autolaunch graduation"},
    {"autolaunch.first_settled_auction", 1, 10, "First Autolaunch auction settled"},
    {"autolaunch.token_staked", 1, 40, "Autolaunch token staked"},
    {"keyfleet.first_membership", 1, 10, "First Keyfleet membership"},
    {"keyfleet.first_reveal", 1, 5, "First Keyfleet key revealed"},
    {"keyfleet.first_authorized_agent", 1, 10, "First agent authorized on Keyfleet"},
    {"keyfleet.first_message", 1, 5, "First Keyfleet message"},
    {"keyfleet.first_vote", 1, 10, "First Keyfleet vote"},
    {"keyfleet.integration.twigpine", 1, 10, "Twigpine used with Keyfleet"},
    {"keyfleet.integration.activegraph", 1, 10, "ActiveGraph used with Keyfleet"},
    {"template.first_agent_note", 1, 10, "First note written by your agent"}
  ]
  @activity [
    {"autolaunch.auction_created", 1, 20, 1, "day", "Autolaunch auction created"},
    {"autolaunch.auction_bid", 1, 20, 1, "day", "Autolaunch auction bid"},
    {"autolaunch.token_traded", 1, 10, 1, "day", "Autolaunch token trade"},
    {"keyfleet.key_bought", 1, 10, 5, "day", "Keyfleet key bought"},
    {"patchbay.offer_bid_placed", 1, 5, 10, "day", "Patchbay Offer placed"},
    {"patchbay.report_published", 1, 10, 1, "day", "Patchbay report published"},
    {"patchbay.reply_published", 1, 5, 1, "day", "Patchbay reply published"}
  ]

  @credits {"credits.purchase_settled", 1, "Credits bought"}
  @labels Map.new(
            [Tuple.delete_at(@credits, 1)] ++
              for({id, _version, _points, label} <- @milestones, do: {id, label}) ++
              for({id, _version, _points, _count, _period, label} <- @activity, do: {id, label})
          )

  # One-time rules an account could already meet before the start: they earn at the
  # start, through RegentPoints.StartAwards, without the person doing anything.
  @start_rules ~w(account.activated social.x social.github social.farcaster agent.activated)

  @doc "The customer name of every catalog rule, including the source app."
  def label(id), do: Map.fetch!(@labels, id)

  def catalog do
    milestones =
      Enum.map(@milestones, fn {id, version, points, _label} ->
        rule(id, version, "milestone", points, 1, "lifetime")
      end)

    activity =
      Enum.map(@activity, fn {id, version, points, count, period, _label} ->
        rule(id, version, "activity", points, count, period)
      end)

    {credits, version, _label} = @credits

    [rule(credits, version, "credits", nil, nil, "day") | milestones ++ activity]
  end

  def config, do: Application.get_all_env(:regent_points)
  def unit, do: @unit
  def program, do: Keyword.fetch!(config(), :program_id)
  def milestone_total, do: Enum.sum(Enum.map(@milestones, &elem(&1, 2)))
  def enabled?(id), do: id in Keyword.get(config(), :approved_rules, []) and adapter(id) != nil
  def adapter(id), do: config() |> Keyword.get(:adapters, %{}) |> Map.get(id)

  @doc """
  The rules a site's Points page lists: approved and given a source here. The
  approved list is the one switch; a rule taken off it leaves the page too.
  """
  def tracked, do: Enum.filter(catalog(), &enabled?(&1["id"]))

  @doc "The one-time rules whose state from before the start earns at the start."
  def start_rules, do: @start_rules
  def start_rule?(id), do: id in @start_rules

  @doc "The catalog rules that earn right now."
  def active,
    do: Enum.filter(catalog(), &match?({:ok, _}, snapshot(&1["id"], DateTime.utc_now())))

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

  @doc """
  The daily limit a rule's points count against: Credits bought have their
  own, and every repeat action shares one, whoever acted, the person or any
  of their agents. One-time rules count against none.
  """
  def allowance_scope(%{"category" => "credits"}), do: "credits"
  def allowance_scope(%{"category" => "activity"}), do: "activity:account"
  def allowance_scope(_rule), do: nil

  def window("lifetime", _at), do: {~D[1970-01-01], nil}

  def window("day", at) do
    day = at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()
    {day, Date.add(day, 1)}
  end

  def daily_cap("credits"), do: 50 * @unit
  def daily_cap("activity:account"), do: 100 * @unit

  @doc "The apps the daily rules among `rules` come from."
  def daily_apps(rules) do
    for %{"category" => "activity", "id" => id} <- rules,
        uniq: true,
        do: hd(String.split(id, "."))
  end

  def activity_app?(app), do: app in daily_apps(catalog())

  @doc "What a rule's count is kept under: one count per action for the person and their agents."
  def count_scope(rule), do: rule["milestone_key"] || rule["id"]

  defp rule(id, version, category, points, count, period),
    do: %{
      "id" => id,
      "version" => version,
      "category" => category,
      "points" => points,
      "count" => count,
      "period" => period,
      "daily_caps_micro" => Map.new(["credits", "activity:account"], &{&1, daily_cap(&1)}),
      "micro_points_per_atomic_usdc" => if(category == "credits", do: 1),
      "milestone_key" => if(category == "milestone", do: id)
    }
end

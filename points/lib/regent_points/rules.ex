defmodule RegentPoints.Rules do
  @moduledoc """
  Finite proposed catalog. Nothing earns until the founder approves a rule,
  its source adapter is installed, and the program has an explicit start time.
  Rates are pinned on intake; retries never apply today's pricing to old work.

  A rule's id never changes. A changed rule keeps its id and gets the next
  version, so what an account earned under the old version still counts
  against the new one; a new id is only for a new action.

  A spending rule earns one point per dollar a payment's evidence proves, up to
  100 dollars per account per UTC day (Sean, 6 November 2026). It earns beside
  the action's fixed points, under its own daily limit.
  """
  @unit 1_000_000
  @points_per_dollar 1
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
  @spending [
    {"keyfleet.key_spend", 1, "Keyfleet key spending"},
    {"patchbay.payment_spend", 1, "Patchbay payment spending"},
    {"template.pinned_note_spend", 1, "Pinned note spending"},
    {"autolaunch.auction_bid_spend", 1, "Autolaunch bid spending"},
    {"autolaunch.token_buy_spend", 1, "Autolaunch token buy spending"}
  ]

  @labels Map.new(
            for({id, _version, _points, label} <- @milestones, do: {id, label}) ++
              for({id, _version, _points, _count, _period, label} <- @activity, do: {id, label}) ++
              for({id, _version, label} <- @spending, do: {id, label})
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

    spending =
      Enum.map(@spending, fn {id, version, _label} ->
        %{
          "id" => id,
          "version" => version,
          "category" => "spending",
          "points_per_dollar" => @points_per_dollar,
          "count" => nil,
          "period" => "day",
          "daily_caps_micro" => %{"spending:account" => daily_cap("spending:account")},
          "milestone_key" => nil
        }
      end)

    milestones ++ activity ++ spending
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

  @doc "A rule's points before limits: fixed, or one per dollar the payment's evidence proves."
  def base_micro(%{"points" => points}, _evidence) when is_integer(points),
    do: {:ok, points * @unit}

  def base_micro(%{"category" => "spending", "points_per_dollar" => rate}, %{
        "usd_micros" => usd
      })
      when is_integer(rate) and is_integer(usd) and usd > 0,
      do: {:ok, usd * rate}

  def base_micro(_rule, _evidence), do: {:error, :invalid_rule_snapshot}

  @doc """
  The daily limit a rule's points count against: every repeat action shares
  one, and every spending rule shares another, whoever acted, the person or
  any of their agents. One-time rules count against none.
  """
  def allowance_scope(%{"category" => "activity"}), do: "activity:account"
  def allowance_scope(%{"category" => "spending"}), do: "spending:account"
  def allowance_scope(_rule), do: nil

  def window("lifetime", _at), do: {~D[1970-01-01], nil}

  def window("day", at) do
    day = at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()
    {day, Date.add(day, 1)}
  end

  def daily_cap("activity:account"), do: 100 * @unit
  def daily_cap("spending:account"), do: 100 * @points_per_dollar * @unit

  @doc "Points a spending rule gives for each dollar."
  def points_per_dollar, do: @points_per_dollar

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
      "daily_caps_micro" => %{"activity:account" => daily_cap("activity:account")},
      "milestone_key" => if(category == "milestone", do: id)
    }
end

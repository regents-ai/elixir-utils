defmodule Review3.Source do
  @moduledoc false
  # Source facts kept in a public ETS table, so reports made from several
  # processes at once never lose each other's facts.
  def table do
    if :ets.whereis(__MODULE__) == :undefined do
      try do
        :ets.new(__MODULE__, [:named_table, :public, :set])
      rescue
        ArgumentError -> :ok
      end
    end

    __MODULE__
  end

  def put(key, facts), do: :ets.insert(table(), {key, facts})

  def verify(%{"source_event_key" => key}) do
    case :ets.lookup(table(), key) do
      [{^key, facts}] -> {:ok, facts}
      [] -> :error
    end
  end
end

defmodule Review3.People do
  @moduledoc false
  @behaviour RegentPoints.Accounts
  @impl true
  def human(_id), do: %{wallet_address: nil, wallet_addresses: []}
  @impl true
  def agent_names(_id, _ids), do: {:ok, %{}}
  @impl true
  def people(ids), do: {:ok, Map.new(ids, &{&1, %{name: nil, wallet: nil}})}
end

defmodule Review3.Helpers do
  @moduledoc false
  require Ash.Query
  alias RegentPoints.{CapUsage, Entry, Event, Rules, Store}

  @spending ~w(keyfleet.key_spend patchbay.payment_spend template.pinned_note_spend autolaunch.auction_bid_spend)
  @activity ~w(patchbay.reply_published keyfleet.key_bought patchbay.offer_bid_placed autolaunch.auction_bid)
  @milestones ~w(account.activated keyfleet.first_message)

  def spending, do: @spending
  def rules, do: @activity ++ @milestones ++ @spending
  def limit, do: 100_000_000
  def ceiling, do: 1_000_000_000_000_000
  def start, do: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -5 * 86_400)
  def midnight, do: DateTime.new!(Date.add(Date.utc_today(), -2), ~T[00:00:00])

  # Sets the program up the way a site does and returns a function that puts
  # the earlier settings back.
  def configure(program \\ "review3-test") do
    Review3.Source.table()
    keys = [:program_id, :starts_at, :approved_rules, :adapters, :accounts]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})
    Application.put_env(:regent_points, :program_id, program)
    Application.put_env(:regent_points, :starts_at, start())
    Application.put_env(:regent_points, :approved_rules, rules())
    Application.put_env(:regent_points, :adapters, Map.new(rules(), &{&1, Review3.Source}))
    Application.put_env(:regent_points, :accounts, Review3.People)

    fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end
  end

  def hex(bytes), do: Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)
  def tx, do: "0x" <> hex(32)

  def payment(usd, overrides \\ %{}) do
    Map.merge(
      %{
        "usd_micros" => usd,
        "payer" => "0x" <> hex(20),
        "token" => "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
        "token_amount" => Integer.to_string(usd),
        "token_decimals" => 6,
        "price_usd" => "1",
        "price_source" => "face_value",
        "chain_id" => 8453,
        "block_number" => 38_000_000,
        "tx_hash" => tx(),
        "log_index" => 7
      },
      overrides
    )
  end

  def facts(rule, account, at, evidence, opts \\ []) do
    app = Keyword.get(opts, :app, rule |> String.split(".") |> hd())
    key = Keyword.get_lazy(opts, :key, fn -> "r3-" <> hex(16) end)

    extra =
      if String.starts_with?(rule, "keyfleet."),
        do: %{"key_id" => key, "ownership_epoch" => "1"},
        else: %{}

    %{
      source_app: Keyword.get(opts, :facts_app, app),
      source_kind: Keyword.get(opts, :kind, "test"),
      source_event_key: key,
      account_id: account,
      actor_kind: "human",
      actor_id: to_string(account),
      source_action_at: at,
      qualified_at: Keyword.get(opts, :qualified_at, at),
      evidence_ref: "test:" <> key,
      evidence: Map.merge(evidence, extra)
    }
  end

  # Reports the way a site does. Returns {source key, result of record_event}.
  def report(rule, account, at, evidence, opts \\ []) do
    facts = facts(rule, account, at, evidence, opts)
    app = Keyword.get(opts, :app, rule |> String.split(".") |> hd())
    Review3.Source.put(facts.source_event_key, facts)

    {facts.source_event_key,
     RegentPoints.record_event(
       %{
         rule_id: rule,
         source_app: app,
         source_kind: facts.source_kind,
         source_event_key: facts.source_event_key
       },
       actor: Store.system()
     )}
  end

  def pay(rule, account, at, usd_or_evidence, opts \\ [])

  def pay(rule, account, at, usd, opts) when is_integer(usd),
    do: pay(rule, account, at, payment(usd), opts)

  def pay(rule, account, at, evidence, opts) do
    {key, {:ok, _}} = report(rule, account, at, evidence, opts)
    key
  end

  def events(key) do
    Event
    |> Ash.Query.filter(source_event_key == ^key)
    |> then(&RegentPoints.read_events!(query: &1, actor: Store.system()))
  end

  def entry(key) do
    key
    |> events()
    |> Enum.flat_map(fn event ->
      Entry
      |> Ash.Query.filter(event_id == ^event.id and is_nil(reversal_of_entry_id))
      |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
    end)
    |> List.first()
  end

  def earned(key), do: with(%{points_micro_delta: points} <- entry(key), do: points)

  def rejections(key) do
    for rejection <- RegentPoints.read_rejections!(actor: Store.system()),
        rejection.source["source_event_key"] == key,
        do: rejection.reason_code
  end

  def outcome(evidence, rule \\ "patchbay.payment_spend", opts \\ []) do
    {key, {:ok, _}} = report(rule, person(), midnight(), evidence, opts)
    {earned(key), rejections(key)}
  end

  def payment_row(%{"chain_id" => chain, "tx_hash" => tx, "log_index" => log}) do
    scope = "payment:" <> Store.digest({chain, tx, log})

    CapUsage
    |> Ash.Query.filter(account_id == 0 and cap_scope == ^scope)
    |> then(&RegentPoints.read_caps!(query: &1, actor: Store.system()))
    |> case do
      [cap] -> {cap.award_count, cap.points_micro}
      [] -> nil
    end
  end

  def day_row(account, at, scope \\ "spending:account") do
    day = DateTime.to_date(at)

    CapUsage
    |> Ash.Query.filter(account_id == ^account and cap_scope == ^scope and window_start == ^day)
    |> then(&RegentPoints.read_caps!(query: &1, actor: Store.system()))
    |> case do
      [cap] -> {cap.award_count, cap.points_micro}
      [] -> nil
    end
  end

  def person do
    %{rows: [[id]]} =
      RegentPoints.Repo.query!(
        "INSERT INTO regent_names.platform_human_users DEFAULT VALUES RETURNING id"
      )

    id
  end

  def entries(account, category \\ nil) do
    Entry
    |> Ash.Query.filter(account_id == ^account and program_id == ^Rules.program())
    |> Ash.Query.sort(recorded_at: :asc)
    |> then(&RegentPoints.read_entries!(query: &1, actor: Store.system()))
    |> Enum.filter(&(category == nil or &1.category == category))
  end

  def total(account), do: Enum.sum(Enum.map(entries(account), & &1.points_micro_delta))
  def reader(account), do: %{role: :human, human_account_id: account}
  def system, do: Store.system()
end

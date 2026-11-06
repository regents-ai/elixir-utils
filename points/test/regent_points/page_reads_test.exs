defmodule RegentPoints.PageReadsTest do
  # What the Points page reads: one person's figures by day and what they have done
  # of each action, and the board a site reads once for every reader. Actions are
  # recorded the way a site records them, on a real database, with Oban running each
  # job as it is queued.
  use ExUnit.Case, async: false
  use ExUnitProperties
  require Ash.Query
  alias RegentPoints.{Leaderboard, Store}

  defmodule Source do
    @moduledoc false
    def verify(%{"source_event_key" => key}),
      do: Map.fetch(Application.get_env(:regent_points, :test_facts, %{}), key)
  end

  defmodule People do
    @moduledoc false
    # A site's account lookups: a public name and pictures, and nothing else.
    @behaviour RegentPoints.Accounts

    @impl true
    def human(_id), do: %{wallet_address: nil, wallet_addresses: []}

    @impl true
    def agent_names(_id, _ids), do: {:ok, %{}}

    @impl true
    def people(ids),
      do:
        {:ok,
         Map.new(
           ids,
           &{&1, %{name: "Person #{&1}", squares: nil, picture: nil, wallet: "0xsecret"}}
         )}
  end

  @rules ~w(account.activated social.x social.github social.farcaster)
  @start DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -5 * 86_400)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentPoints.Repo)
    keys = [:program_id, :starts_at, :approved_rules, :adapters, :accounts, :test_facts]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    Application.put_env(:regent_points, :program_id, "page-reads-test")
    Application.put_env(:regent_points, :starts_at, @start)
    Application.put_env(:regent_points, :approved_rules, @rules)
    Application.put_env(:regent_points, :adapters, Map.new(@rules, &{&1, Source}))
    Application.put_env(:regent_points, :accounts, People)
    :ok
  end

  test "today and yesterday each count only their own UTC day" do
    account = person()
    now = DateTime.utc_now()
    earn("account.activated", account, DateTime.add(now, -3 * 86_400))
    earn("social.x", account, DateTime.add(now, -86_400))

    summary = RegentPoints.summary!(actor: reader(account))

    assert summary.balance_micro == 35_000_000
    assert summary.earned_yesterday_micro == 10_000_000
    assert summary.earned_today_micro == 0
  end

  test "an action done once is counted done, and one not done is not" do
    account = person()
    earn("account.activated", account, DateTime.utc_now())

    assert %{"account.activated" => 1, "social.x" => 0} =
             RegentPoints.summary!(actor: reader(account)).done
  end

  test "the board orders by total, shares a place on a tie and leaves out zero" do
    [first, level_a, level_b, last, none] = for _ <- 1..5, do: person()
    now = DateTime.utc_now()

    for account <- [first, level_a, level_b], do: earn("account.activated", account, now)
    earn("social.x", first, now)
    earn("social.x", last, now)
    RegentPoints.open_account!(%{id: none}, actor: Store.system())

    assert %{top: top, totals: totals} = RegentPoints.leaderboard!(actor: Store.system())

    assert Enum.map(top, &{&1.rank, &1.points_micro}) == [
             {1, 35_000_000},
             {2, 25_000_000},
             {2, 25_000_000},
             {4, 10_000_000}
           ]

    # Inside a tie the lower account id comes first, so every read agrees.
    assert Enum.map(top, & &1.account_id) ==
             [first, min(level_a, level_b), max(level_a, level_b), last]

    assert totals == [35_000_000, 25_000_000, 25_000_000, 10_000_000]
    assert Leaderboard.place(totals, 10_000_000) == 4
    assert Leaderboard.place(totals, 0) == nil
  end

  test "the board lists ten rows and every total, for a place below them" do
    now = DateTime.utc_now()
    for _ <- 1..10, do: earn("account.activated", person(), now)
    earn("social.x", person(), now)

    assert %{top: top, totals: totals} = RegentPoints.leaderboard!(actor: Store.system())
    assert length(top) == 10
    assert length(totals) == 11
    assert Leaderboard.place(totals, 10_000_000) == 11
  end

  # The board carries account ids for the site to keep, so only the site reads it.
  test "a person cannot read the board themselves" do
    account = person()
    earn("account.activated", account, DateTime.utc_now())

    assert {:error, %Ash.Error.Forbidden{}} = RegentPoints.leaderboard(actor: reader(account))
  end

  # A row carries the public name and pictures the site supplied, its place and its
  # total, and the account id the site needs to mark the reader's own row: no
  # wallet or anything else the site's lookup happened to return.
  test "a row holds a name, pictures, a place, a total and the account id" do
    earn("account.activated", person(), DateTime.utc_now())

    assert %{top: [row]} = RegentPoints.leaderboard!(actor: Store.system())

    assert row |> Map.keys() |> Enum.sort() ==
             [:account_id, :name, :picture, :points_micro, :rank, :squares]
  end

  # Each account earns some of four one-time awards (25, 10, 10 and 10), so many
  # are level on points; the accounts from earlier runs stay, so the field grows.
  property "a place from the board's totals is the count of accounts above, plus one" do
    # Each number's bits pick which of the four awards one account earns.
    check all(earned <- list_of(integer(0..15), min_length: 1, max_length: 6), max_runs: 12) do
      now = DateTime.utc_now()

      for bits <- earned do
        account = person()

        for {rule, bit} <- Enum.with_index(@rules),
            Bitwise.band(bits, Bitwise.bsl(1, bit)) != 0,
            do: earn(rule, account, now)
      end

      %{totals: totals} = RegentPoints.leaderboard!(actor: Store.system())

      for account <- RegentPoints.read_accounts!(load: [:balance_micro], actor: Store.system()) do
        assert Leaderboard.place(totals, account.balance_micro) ==
                 counted_place(account.balance_micro)
      end
    end
  end

  # The per-reader count the board replaced: every account with more points, plus one.
  defp counted_place(0), do: nil

  defp counted_place(total) do
    ahead = Ash.Query.filter(RegentPoints.Account, balance_micro > ^total)
    Ash.count!(ahead, actor: Store.system()) + 1
  end

  defp reader(account), do: %{role: :human, human_account_id: account}

  defp person do
    %{rows: [[id]]} =
      RegentPoints.Repo.query!(
        "INSERT INTO regent_names.platform_human_users DEFAULT VALUES RETURNING id"
      )

    id
  end

  # A linked social account is proven by the account it names.
  defp evidence("social." <> _, key), do: %{"subject_key" => key}
  defp evidence(_rule_id, _key), do: %{}

  # Saves the source's facts and records the action the way a site does.
  defp earn(rule_id, account, at) do
    key = "#{rule_id}:#{account}"

    facts = %{
      source_app: "site-a",
      source_kind: "test",
      source_event_key: key,
      account_id: account,
      actor_kind: "human",
      actor_id: to_string(account),
      source_action_at: at,
      qualified_at: at,
      evidence_ref: "test:" <> key,
      evidence: evidence(rule_id, key)
    }

    saved = Application.get_env(:regent_points, :test_facts, %{})
    Application.put_env(:regent_points, :test_facts, Map.put(saved, key, facts))

    assert {:ok, _} =
             RegentPoints.record_event(
               %{
                 rule_id: rule_id,
                 source_app: "site-a",
                 source_kind: "test",
                 source_event_key: key
               },
               actor: Store.system()
             )
  end
end

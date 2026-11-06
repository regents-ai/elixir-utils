defmodule RegentPoints.PageReadsTest do
  # What the Points page reads for one person: their figures by day, what they have
  # done of each action, and the leaderboard. Actions are recorded the way a site
  # records them, on a real database, with Oban running each job as it is queued.
  use ExUnit.Case, async: false
  alias RegentPoints.Store

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

  @rules ~w(account.activated social.x credits.purchase_settled)
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

  test "the leaderboard orders by total, shares a place on a tie and leaves out zero" do
    [first, level_a, level_b, last, none] = for _ <- 1..5, do: person()
    now = DateTime.utc_now()

    for account <- [first, level_a, level_b], do: earn("account.activated", account, now)
    earn("social.x", first, now)
    earn("social.x", last, now)
    RegentPoints.open_account!(%{id: none}, actor: Store.system())

    assert %{top: top, you: you} = RegentPoints.leaderboard!(actor: reader(last))

    assert Enum.map(top, &{&1.rank, &1.points_micro}) == [
             {1, 35_000_000},
             {2, 25_000_000},
             {2, 25_000_000},
             {4, 10_000_000}
           ]

    assert Enum.map(top, & &1.you?) == [false, false, false, true]
    assert you == %{rank: 4, points_micro: 10_000_000}
  end

  test "a reader with no points has no place" do
    earn("account.activated", person(), DateTime.utc_now())
    assert %{you: nil, top: [_]} = RegentPoints.leaderboard!(actor: reader(person()))
  end

  test "a reader below the listed ten still gets their own place" do
    now = DateTime.utc_now()
    for _ <- 1..10, do: earn("account.activated", person(), now)
    reader = person()
    earn("social.x", reader, now)

    assert %{top: top, you: %{rank: 11, points_micro: 10_000_000}} =
             RegentPoints.leaderboard!(actor: reader(reader))

    assert length(top) == 10
    refute Enum.any?(top, & &1.you?)
  end

  # A row carries the public name and pictures the site supplied and the total:
  # no account id, wallet or anything else the site's lookup happened to return.
  test "nothing but a name, pictures, a place and a total leaves an account" do
    account = person()
    earn("account.activated", account, DateTime.utc_now())

    assert %{top: [row]} = RegentPoints.leaderboard!(actor: reader(account))

    assert row |> Map.keys() |> Enum.sort() ==
             [:name, :picture, :points_micro, :rank, :squares, :you?]
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

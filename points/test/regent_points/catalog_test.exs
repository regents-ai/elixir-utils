defmodule RegentPoints.CatalogTest do
  use ExUnit.Case, async: false
  alias RegentPoints.Rules

  @hidden "template.first_agent_note"

  setup do
    keys = [:starts_at, :approved_rules, :adapters]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    :ok
  end

  test "the one-time rules, their versions and points" do
    assert for(
             %{"category" => "milestone"} = rule <- Rules.catalog(),
             do: {rule["id"], rule["version"], rule["points"]}
           ) == [
             {"account.activated", 1, 25},
             {"social.x", 1, 10},
             {"social.github", 1, 10},
             {"social.farcaster", 1, 10},
             {"agent.activated", 1, 25},
             {"autolaunch.first_launch", 1, 25},
             {"autolaunch.first_graduation", 2, 25},
             {"autolaunch.token_staked", 1, 40},
             {"keyfleet.first_membership", 2, 25},
             {"keyfleet.first_authorized_agent", 2, 25},
             {"keyfleet.first_message", 2, 25},
             {"keyfleet.first_vote", 2, 25},
             {"keyfleet.integration.git", 1, 20},
             {"keyfleet.integration.marimo", 1, 20},
             {"keyfleet.integration.activegraph", 2, 20},
             {"cloak.first_download", 1, 25},
             {@hidden, 1, 10}
           ]

    assert Rules.milestone_total() == 365
  end

  test "every catalog rule is listed except the hidden one" do
    ids = Enum.map(Rules.catalog(), & &1["id"])
    assert Enum.map(Rules.listed(), & &1["id"]) == ids -- [@hidden]

    assert Enum.sum(for %{"category" => "milestone"} = rule <- Rules.listed(), do: rule["points"]) ==
             355
  end

  test "the groups hold every listed rule once, each under its own site, in the page's order" do
    groups = Rules.groups()

    assert Enum.map(groups, & &1.site) == [
             "Account",
             "Autolaunch",
             "Keyfleet",
             "Patchbay",
             "Cloak"
           ]

    assert Enum.flat_map(groups, & &1.rules) |> Enum.sort_by(& &1["id"]) ==
             Enum.sort_by(Rules.listed(), & &1["id"])

    apps =
      Map.new(groups, fn %{site: site, rules: rules} ->
        {site, rules |> Enum.map(&hd(String.split(&1["id"], "."))) |> Enum.uniq() |> Enum.sort()}
      end)

    assert apps == %{
             "Account" => ["account", "agent", "social"],
             "Autolaunch" => ["autolaunch"],
             "Keyfleet" => ["keyfleet"],
             "Patchbay" => ["patchbay"],
             "Cloak" => ["cloak"]
           }
  end

  test "the hidden rule earns once approved with a source, though no page lists it" do
    Application.put_env(:regent_points, :starts_at, ~U[2020-01-01 00:00:00Z])
    Application.put_env(:regent_points, :approved_rules, [@hidden])
    Application.put_env(:regent_points, :adapters, %{@hidden => __MODULE__})

    assert Rules.enabled?(@hidden)
    assert [%{"id" => @hidden}] = Rules.tracked()

    assert {:ok, %{"id" => @hidden, "points" => 10}} =
             Rules.snapshot(@hidden, ~U[2020-01-02 00:00:00Z])

    refute Enum.any?(Rules.listed(), &(&1["id"] == @hidden))
  end
end

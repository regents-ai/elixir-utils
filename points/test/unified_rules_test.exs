defmodule RegentPoints.UnifiedRulesTest do
  use ExUnit.Case, async: false
  alias RegentPoints.Rules

  setup do
    keys = [:starts_at, :unified_activity_starts_at, :approved_rules, :adapters]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    Application.put_env(:regent_points, :starts_at, ~U[2020-01-01 00:00:00Z])
    Application.put_env(:regent_points, :unified_activity_starts_at, ~U[2020-01-02 00:00:00Z])
    Application.put_env(:regent_points, :approved_rules, ["patchbay.reply_published"])
    Application.put_env(:regent_points, :adapters, %{"patchbay.reply_published" => __MODULE__})
    :ok
  end

  test "delayed events retain their rule version, while new user and agent actions share both caps" do
    assert {:ok, old} = Rules.snapshot("patchbay.reply_published", ~U[2020-01-01 23:59:59Z])
    assert {:ok, new} = Rules.snapshot("patchbay.reply_published", ~U[2020-01-02 00:00:00Z])
    assert old["version"] == 1 and new["version"] == 2
    assert old["daily_caps_micro"]["activity:human"] == 50_000_000

    assert new["daily_caps_micro"] == %{
             "credits" => 100_000_000,
             "activity:account" => 100_000_000
           }

    assert Rules.count_scope(new, "human") == Rules.count_scope(new, "agent")
    assert Rules.allowance_scope(new, "human") == Rules.allowance_scope(new, "agent")
    assert Rules.count_scope(old, "human") != Rules.count_scope(old, "agent")
    assert new["points"] == old["points"] and new["count"] == old["count"]
    assert Rules.period(1) == {~U[2020-01-01 00:00:00Z], ~U[2020-01-31 00:00:00Z]}
    Application.put_env(:regent_points, :approved_rules, [])

    assert {:error, :rule_not_active} =
             Rules.snapshot("patchbay.reply_published", ~U[2020-01-02 00:00:00Z])
  end

  test "cutover cannot silently split one UTC day or reset the program" do
    Application.put_env(:regent_points, :unified_activity_starts_at, ~U[2020-01-02 00:00:01Z])
    assert_raise ArgumentError, fn -> Rules.catalog() end
    Application.put_env(:regent_points, :unified_activity_starts_at, ~U[2019-12-31 00:00:00Z])
    assert_raise ArgumentError, fn -> Rules.catalog() end
  end
end

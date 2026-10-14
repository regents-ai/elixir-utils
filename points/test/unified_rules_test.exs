defmodule RegentPoints.UnifiedRulesTest do
  use ExUnit.Case, async: false
  alias RegentPoints.Rules

  setup do
    keys = [:starts_at, :approved_rules, :adapters]
    previous = Map.new(keys, &{&1, Application.fetch_env(:regent_points, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:regent_points, key, value)
        {key, :error} -> Application.delete_env(:regent_points, key)
      end)
    end)

    Application.put_env(:regent_points, :starts_at, ~U[2020-01-01 00:00:00Z])
    Application.put_env(:regent_points, :approved_rules, ["patchbay.reply_published"])
    Application.put_env(:regent_points, :adapters, %{"patchbay.reply_published" => __MODULE__})
    :ok
  end

  test "a person and their agents share one count per action and one daily limit" do
    assert {:error, :rule_not_active} =
             Rules.snapshot("patchbay.reply_published", ~U[2019-12-31 23:59:59Z])

    assert {:ok, rule} = Rules.snapshot("patchbay.reply_published", ~U[2020-01-02 00:00:00Z])

    assert rule["daily_caps_micro"] == %{
             "credits" => 50_000_000,
             "activity:account" => 100_000_000
           }

    assert Rules.count_scope(rule) == "patchbay.reply_published"
    assert Rules.allowance_scope(rule) == "activity:account"
    assert rule["points"] == 5 and rule["count"] == 1
    assert Rules.period(1) == {~U[2020-01-01 00:00:00Z], ~U[2020-01-31 00:00:00Z]}
    Application.put_env(:regent_points, :approved_rules, [])

    assert {:error, :rule_not_active} =
             Rules.snapshot("patchbay.reply_published", ~U[2020-01-02 00:00:00Z])
  end
end

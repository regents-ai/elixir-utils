defmodule RegentCredits.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Regent Credits: one prepaid balance per person, shared by every Regent site."

  def project do
    [
      app: :regent_credits,
      version: @version,
      elixir: "~> 1.19.5",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
      deps: deps(),
      usage_rules: usage_rules(),
      aliases: aliases(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [check: :test, precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.34 and >= 3.34.3"},
      # 2.13.1 and later build upserts against the wrong schema.
      {:ash_postgres, "== 2.13.0"},
      {:ash_double_entry, "~> 1.0.19"},
      {:ash_money, "~> 0.2.6"},
      {:ash_oban, "~> 0.9.0"},
      {:ex_money_sql, "~> 2.1"},
      {:simple_sat, "~> 0.1"},
      {:regent_chain, path: "../chain"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:usage_rules, "~> 1.2.8", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:credo_ash, path: "../credo_ash", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        "lib",
        "priv",
        "mix.exs"
      ],
      licenses: ["MIT"],
      links: %{
        "Source" => "https://github.com/regents-ai/elixir-utils/tree/main/credits"
      }
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "credo --strict",
        "usage_rules.sync --check",
        "test --warnings-as-errors"
      ],
      precommit: ["check"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  # `mix usage_rules.sync` writes the marked block at the end of AGENTS.md: how to
  # read the installed version's docs, and links to each package's own rules in deps/.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: []},
        {:usage_rules, sub_rules: :all, main: false, link: :markdown},
        {:ash, link: :markdown},
        {~r/^ash_/, link: :markdown}
      ]
    ]
  end
end

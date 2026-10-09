defmodule RegentPayments.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Regent Payments: paid actions for every Regent site, in USDC on Base."

  def project do
    [
      app: :regent_payments,
      version: @version,
      elixir: "~> 1.19",
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
    [extra_applications: [:logger, :crypto]]
  end

  def cli do
    [preferred_envs: [check: :test, precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.34 and >= 3.34.3"},
      # 2.13.1 through 2.14.2 send upserts to the public schema, ignoring the
      # repo's prefix that picks each site's schema on the shared database.
      {:ash_postgres, "== 2.13.0"},
      {:simple_sat, "~> 0.1"},
      {:x402, "0.9.0"},
      {:ethers, "0.8.0"},
      {:ex_secp256k1, "~> 0.8.0"},
      {:ex_keccak, "~> 0.7.8"},
      {:finch, "~> 0.19"},
      {:req, "~> 0.5"},
      {:plug_crypto, "~> 2.1"},
      {:regent_chain, path: "../../chain"},
      {:regent_format, path: "../../format"},
      {:regent_agents, path: "../agents"},
      {:bandit, "~> 1.5", only: :test},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:usage_rules, "~> 1.2.8", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:credo_ash, path: "../../credo_ash", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "LICENSE",
        "lib",
        "priv",
        "mix.exs"
      ],
      licenses: ["MIT"],
      links: %{
        "Source" => "https://github.com/regents-ai/elixir-utils/tree/main/ash_components/payments"
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
      main: "RegentPayments",
      extras: ["CHANGELOG.md"]
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

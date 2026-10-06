defmodule AgentEns.MixProject do
  use Mix.Project

  @version "0.1.1"
  @description "Elixir-first ENSIP-25 library for ENS and ERC-8004 verification, planning, and unsigned link preparation."

  def project do
    [
      app: :ens_elixir,
      version: @version,
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir, :app],
      description: @description,
      package: package(),
      deps: deps(),
      usage_rules: usage_rules(),
      aliases: aliases(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test, precommit: :test]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7"},
      {:idna, "~> 7.1"},
      {:jason, "~> 1.4"},
      {:siwa, path: "../siwa/siwa-elixir/apps/siwa"},
      {:ex_keccak, "~> 0.7.8"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:usage_rules, "~> 1.2.8", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "usage_rules.sync --check",
        "test --warnings-as-errors"
      ],
      precommit: ["check"]
    ]
  end

  defp package do
    [
      name: "ens_elixir",
      licenses: ["MIT", "Apache-2.0"],
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "LICENSE-APACHE",
        "LICENSE-MIT",
        "README.md",
        "USAGE.md",
        "lib",
        "mix.exs"
      ],
      links: %{
        "ENSIP-25" => "https://docs.ens.domains/ensip/25",
        "Upstream Rust SDK" => "https://github.com/qntx/ensip25",
        "Source" => "https://github.com/regents-ai/elixir-utils/tree/main/ens"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "USAGE.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Start Here": [AgentEns, AgentEns.Error, AgentEns.TxRequest],
        "Verification and Keys": [AgentEns.ERC7930, AgentEns.RecordKey, AgentEns.Verify],
        "Reading and Planning": [AgentEns.Read, AgentEns.Plan, AgentEns.Link],
        "Preparing Updates": [AgentEns.Tx, AgentEns.ERC8004.Registration],
        Support: [AgentEns.Networks, AgentEns.Normalize]
      ]
    ]
  end

  # `mix usage_rules.sync` writes the marked block at the end of AGENTS.md: how to
  # read the installed version's docs, and links to each package's own rules in deps/.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: []},
        {:usage_rules, sub_rules: :all, main: false, link: :markdown}
      ]
    ]
  end
end

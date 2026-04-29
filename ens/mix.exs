defmodule AgentEns.MixProject do
  use Mix.Project

  @version "0.1.0"
  @siwa_requirement "~> 0.1.0"
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
      {:req, "~> 0.5"},
      {:idna, "~> 6.1"},
      {:jason, "~> 1.4"},
      siwa_dependency(),
      {:keccak_ex, "~> 0.4.2"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "test"
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
        "Source" => "https://github.com/regents-ai/regent"
      }
    ]
  end

  defp siwa_dependency do
    if System.get_env("SIWA_HEX_PUBLISH") == "1" do
      {:siwa, @siwa_requirement}
    else
      {:siwa, path: "../siwa/siwa-elixir/apps/siwa"}
    end
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
end

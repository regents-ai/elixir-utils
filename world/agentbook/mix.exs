defmodule AgentWorld.MixProject do
  use Mix.Project

  @version "0.1.0"
  @siwa_requirement "~> 0.1.1"
  @description "Shared Elixir helpers for AgentBook registration, lookup, and AgentKit verification."

  def project do
    [
      app: :agent_world,
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
      {:jason, "~> 1.4"},
      {:keccak_ex, "~> 0.4.2"},
      {:ex_secp256k1, "~> 0.8.0"},
      siwa_dependency(),
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "test --warnings-as-errors"
      ],
      precommit: ["check"]
    ]
  end

  defp siwa_dependency do
    if System.get_env("SIWA_HEX_PUBLISH") == "1" do
      {:siwa, @siwa_requirement}
    else
      {:siwa, path: "../../siwa/siwa-elixir/apps/siwa"}
    end
  end

  defp package do
    [
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "README.md",
        "lib",
        "mix.exs"
      ],
      licenses: ["MIT"],
      links: %{
        "World ID" => "https://docs.world.org/world-id",
        "Source" => "https://github.com/regents-ai/regent/tree/main/elixir-utils/world/agentbook"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Start Here": [AgentWorld, AgentWorld.Error, AgentWorld.TxRequest],
        "Lookup and Registration": [AgentWorld.AgentBook, AgentWorld.Registration],
        Verification: [AgentWorld.Agentkit]
      ]
    ]
  end
end

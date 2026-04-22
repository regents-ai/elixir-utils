defmodule AgentWorld.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Shared Elixir helpers for AgentBook registration, lookup, and AgentKit verification."

  def project do
    [
      app: :agent_world,
      version: @version,
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir, :app],
      description: @description,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:keccak_ex, "~> 0.4.2"},
      {:ex_secp256k1, "~> 0.8.0"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      groups_for_modules: [
        "Start Here": [AgentWorld, AgentWorld.Error, AgentWorld.TxRequest],
        "Lookup and Registration": [AgentWorld.AgentBook, AgentWorld.Registration],
        Verification: [AgentWorld.Agentkit]
      ]
    ]
  end
end

defmodule RegentMCPAgents.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_mcp_agents,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted", "test"]]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  def cli, do: [preferred_envs: [check: :test]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:regent_oauth, path: "../oauth"},
      {:regent_agents, path: "../ash_components/agents"},
      {:regent_agent_access, path: "../agent_access"},
      {:req, "~> 0.7"},
      {:ex_hash_ring, "== 6.0.4", override: true}
    ]
  end
end

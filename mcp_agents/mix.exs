defmodule RegentMCPAgents.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_mcp_agents,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps: deps(),
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted"]]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp deps do
    [
      {:regent_oauth, path: "../oauth"},
      {:regent_agents, path: "../ash_components/agents"},
      {:req, "~> 0.7"},
      {:ex_hash_ring, "== 6.0.4", override: true},
      {:bandit,
       git: "https://github.com/mtrudel/bandit.git",
       ref: "d88b21953c65061f21136ea76a89a4f95a2ac7a1",
       override: true}
    ]
  end
end

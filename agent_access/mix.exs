defmodule RegentAgentAccess.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_agent_access,
      version: "0.2.0",
      elixir: "~> 1.19.5",
      description:
        "Accept negotiation, Vary merging and recovery responses for Regent Phoenix products",
      deps: [
        {:phoenix, "~> 1.8"},
        {:usage_rules, "~> 1.2.8", only: [:dev, :test], runtime: false}
      ],
      usage_rules: usage_rules(),
      aliases: [
        check: [
          "compile --warnings-as-errors",
          "format --check-formatted",
          "usage_rules.sync --check"
        ]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  # `mix usage_rules.sync` writes the marked block at the end of AGENTS.md: how to
  # read the installed version's docs, and links to each package's own rules in deps/.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: []},
        {:usage_rules, sub_rules: :all, main: false, link: :markdown},
        {:phoenix, sub_rules: ["phoenix"], link: :markdown}
      ]
    ]
  end
end

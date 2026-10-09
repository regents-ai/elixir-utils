defmodule RegentPoints.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_points,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: paths(Mix.env()),
      deps: deps(),
      aliases: [
        check: [
          "compile --warnings-as-errors",
          "format --check-formatted",
          "deps.unlock --check-unused",
          "test --warnings-as-errors"
        ]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
  def cli, do: [preferred_envs: [check: :test]]
  defp paths(:prod), do: ["lib"]
  defp paths(_), do: ["lib", "dev"]

  defp deps do
    [
      {:regent_agents, path: "../ash_components/agents"},
      {:ash, "~> 3.34 and >= 3.34.6"},
      {:ash_postgres, "== 2.13.0"},
      {:simple_sat, "~> 0.1"},
      {:oban, "~> 2.24"},
      {:phoenix_pubsub, "~> 2.1"},
      {:decimal, "~> 2.0 or ~> 3.0"},
      {:postgrex, "~> 0.22"},
      {:sourceror, "~> 1.12", only: [:dev, :test], runtime: false}
    ]
  end
end

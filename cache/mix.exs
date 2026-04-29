defmodule RegentCache.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Shared Cachex-backed cache helpers for Regent Elixir apps."

  def project do
    [
      app: :regent_cache,
      version: @version,
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps(),
      aliases: aliases()
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
      {:cachex, "~> 4.1"},
      {:jason, "~> 1.4"}
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
end

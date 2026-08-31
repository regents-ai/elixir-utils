defmodule CredoAsh.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Credo checks for Ash Framework anti-patterns, encoding the ash-regents playbook."

  def project do
    [
      app: :credo_ash,
      version: @version,
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
      deps: deps(),
      aliases: aliases(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [check: :test, precommit: :test]]
  end

  defp deps do
    [
      {:credo, "~> 1.7"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: [".formatter.exs", "CHANGELOG.md", "LICENSE", "README.md", "lib", "mix.exs"],
      licenses: ["MIT"],
      links: %{
        "Source" => "https://github.com/regents-ai/regent/tree/main/elixir-utils/credo_ash"
      }
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "test --warnings-as-errors",
        "credo --strict"
      ],
      precommit: ["check"]
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md", "CHANGELOG.md"]]
  end
end

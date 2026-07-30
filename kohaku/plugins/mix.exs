defmodule KohakuPlugins.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Shared Kohaku plugin host, storage, keystore, and asset primitives for Elixir."

  def project do
    [
      app: :kohaku_plugins,
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
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test --warnings-as-errors"
      ],
      precommit: ["check"]
    ]
  end

  defp package do
    [
      name: "kohaku_plugins",
      licenses: ["MIT"],
      files: [".formatter.exs", "CHANGELOG.md", "README.md", "lib", "mix.exs"],
      links: %{
        "Upstream" => "https://github.com/ethereum/kohaku/tree/master/packages/plugins",
        "Source" => "https://github.com/regents-ai/regent/tree/main/elixir-utils/kohaku/plugins"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end

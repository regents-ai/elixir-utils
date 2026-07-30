defmodule RailgunElixir.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Elixir-first Railgun SDK backed by Kohaku's native Railgun engine."

  def project do
    [
      app: :railgun_elixir,
      version: @version,
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:railgun_native],
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
      {:jason, "~> 1.4"},
      {:kohaku_plugins, path: "../plugins"},
      {:kohaku_provider, path: "../provider"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      check: [
        "cmd cargo build --manifest-path native/railgun_native/Cargo.toml",
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "test --warnings-as-errors"
      ],
      "native.build": [
        "cmd cargo build --release --manifest-path native/railgun_native/Cargo.toml"
      ],
      precommit: ["check"]
    ]
  end

  defp package do
    [
      name: "railgun_elixir",
      licenses: ["MIT"],
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "README.md",
        "lib",
        "native/railgun_native/Cargo.toml",
        "native/railgun_native/src",
        "mix.exs"
      ],
      links: %{
        "Upstream" => "https://github.com/ethereum/kohaku/tree/master/crates/railgun-ts",
        "Source" => "https://github.com/regents-ai/regent/tree/main/elixir-utils/kohaku/railgun"
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

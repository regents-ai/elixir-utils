defmodule Siwa.MixProject do
  use Mix.Project

  @version "0.1.1"
  @description "Shared Elixir library for SIWA wallet sign-in receipts and signed request verification."

  def project do
    [
      app: :siwa,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl],
      mod: {Siwa.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:req, "~> 0.7"},
      {:ex_keccak, "~> 0.7.8"},
      {:ex_secp256k1, "~> 0.8.0"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  # dev/ holds the contract fixture generator and its mix task. A site or the
  # sign-in server compiles this library in :prod, so no release carries the
  # fixtures' test key or receipt secret.
  defp elixirc_paths(:prod), do: ["lib"]
  defp elixirc_paths(_env), do: ["lib", "dev"]

  defp package do
    [
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        "lib",
        "mix.exs"
      ],
      licenses: ["MIT"],
      links: %{
        "Shared SIWA Contract" =>
          "https://github.com/regents-ai/siwa-server/blob/main/priv/static/regent-services-contract.openapiv3.yaml",
        "Source" =>
          "https://github.com/regents-ai/elixir-utils/tree/main/siwa/siwa-elixir/apps/siwa"
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

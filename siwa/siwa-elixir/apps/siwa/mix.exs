defmodule Siwa.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Shared Elixir library for SIWA nonce, message, receipt, and request verification flows."

  def project do
    [
      app: :siwa,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :inets, :ssl],
      mod: {Siwa.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:req, "~> 0.5"},
      {:keccak_ex, "~> 0.4.2"},
      {:ex_secp256k1, "~> 0.8.0"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

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
          "https://github.com/regents-ai/regent/blob/main/regents-cli/docs/regent-services-contract.openapiv3.yaml",
        "Source" =>
          "https://github.com/regents-ai/regent/tree/main/elixir-utils/siwa/siwa-elixir/apps/siwa"
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

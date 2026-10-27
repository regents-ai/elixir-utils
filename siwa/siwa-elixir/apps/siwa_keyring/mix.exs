defmodule SiwaKeyring.MixProject do
  use Mix.Project

  @version "0.2.0"
  @description "Encrypted key store and in-process signing for SIWA flows."

  def project do
    [
      app: :siwa_keyring,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:siwa, in_umbrella: true},
      {:jason, "~> 1.4"},
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
          "https://github.com/regents-ai/siwa-server/blob/main/priv/static/regent-services-contract.openapiv3.yaml",
        "Source" =>
          "https://github.com/regents-ai/elixir-utils/tree/main/siwa/siwa-elixir/apps/siwa_keyring"
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

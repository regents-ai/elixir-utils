defmodule SiwaKeyring.MixProject do
  use Mix.Project

  @version "0.1.0"
  @siwa_requirement "~> 0.1.0"
  @description "Isolated signing service and Elixir client for SIWA flows that need key separation."

  def project do
    [
      app: :siwa_keyring,
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
      extra_applications: [:logger, :crypto, :ssl],
      mod: {SiwaKeyring.Application, []}
    ]
  end

  defp deps do
    [
      siwa_dependency(),
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
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
          "https://github.com/regents-ai/regent/tree/main/elixir-utils/siwa/siwa-elixir/apps/siwa_keyring"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp siwa_dependency do
    if System.get_env("SIWA_HEX_PUBLISH") == "1" do
      {:siwa, @siwa_requirement}
    else
      {:siwa, in_umbrella: true}
    end
  end
end

defmodule RegentERC8004.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_erc8004,
      version: "0.1.0",
      elixir: "~> 1.19.5",
      description: "Small ERC-8004 indexer reads and Phoenix components for Ash applications.",
      deps: deps(),
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted"]],
      package: [
        licenses: ["MIT"],
        files: ~w(lib priv mix.exs .formatter.exs README.md LICENSE NOTICE contract.yaml examples)
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp deps do
    root = System.get_env("REGENT_DEPS_ROOT") || Path.expand("../..", __DIR__)
    ui = System.get_env("REGENT_UI_PATH") || Path.join(root, "design-system/regent_ui")

    [
      {:phoenix_live_view, "~> 1.1.0 or ~> 1.2.0"},
      {:regent_ui, path: ui},
      {:req, "~> 0.5"},
      {:decimal, "~> 2.0 or ~> 3.1"},
      {:jason, "~> 1.4"}
    ]
  end
end

defmodule RegentOAuth.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_oauth,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: [
        {:boruta, "== 2.3.8"},
        # Reads an app's published identity from the address it names.
        {:regent_http, path: "../http"},
        {:plug, "~> 1.18"},
        {:phoenix_html, "~> 4.1"},
        {:postgrex, ">= 0.0.0"}
      ],
      aliases: [
        check: ["compile --warnings-as-errors", "format --check-formatted", "test"]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  def cli, do: [preferred_envs: [check: :test]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end

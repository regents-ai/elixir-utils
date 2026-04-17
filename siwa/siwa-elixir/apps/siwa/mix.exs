defmodule Siwa.MixProject do
  use Mix.Project

  def project do
    [
      app: :siwa,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:keccak_ex, "~> 0.4.2"}
    ]
  end
end

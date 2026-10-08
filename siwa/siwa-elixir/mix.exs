defmodule SiwaElixir.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.1",
      start_permanent: Mix.env() == :prod,
      deps: [{:usage_rules, "~> 1.2.8", only: [:dev, :test], runtime: false}],
      usage_rules: usage_rules(),
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test, precommit: :test]
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "usage_rules.sync --check",
        "siwa.contract --check",
        "test"
      ],
      precommit: ["check"]
    ]
  end

  # `mix usage_rules.sync` writes the marked block at the end of AGENTS.md: how to
  # read the installed version's docs, and links to each package's own rules in deps/.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: []},
        {:usage_rules, sub_rules: :all, main: false, link: :markdown}
      ]
    ]
  end
end

defmodule RegentBlog.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_blog,
      version: "0.2.0",
      elixir: "~> 1.19.5",
      description: "File-authored Markdown blog catalogs for Regent Phoenix products",
      deps: [
        {:mdex, "== 0.13.3"},
        {:yaml_elixir, "~> 2.12"},
        {:floki, "~> 0.38"},
        {:usage_rules, "~> 1.2.8", only: [:dev, :test], runtime: false}
      ],
      usage_rules: usage_rules(),
      aliases: [
        check: [
          "compile --warnings-as-errors",
          "format --check-formatted",
          "usage_rules.sync --check",
          "test --warnings-as-errors"
        ]
      ]
    ]
  end

  def cli, do: [preferred_envs: [check: :test]]

  def application, do: [extra_applications: [:logger]]

  # `mix usage_rules.sync` writes the marked block at the end of AGENTS.md: how to
  # read the installed version's docs, and links to each package's own rules in deps/.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: []},
        {:usage_rules, sub_rules: :all, main: false, link: :markdown},
        {:mdex, link: :markdown}
      ]
    ]
  end
end

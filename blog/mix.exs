defmodule RegentBlog.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_blog,
      version: "0.2.0",
      elixir: "~> 1.19.5",
      description: "File-authored Markdown blog catalogs for Regent Phoenix products",
      deps: [{:mdex, "== 0.13.3"}, {:yaml_elixir, "~> 2.12"}, {:floki, "~> 0.38"}],
      aliases: [
        check: [
          "compile --warnings-as-errors",
          "format --check-formatted",
          "test --warnings-as-errors"
        ]
      ]
    ]
  end

  def cli, do: [preferred_envs: [check: :test]]

  def application, do: [extra_applications: [:logger]]
end

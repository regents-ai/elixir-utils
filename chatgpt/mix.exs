defmodule RegentChatGPT.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Shared ChatGPT account connection primitives for Regent Elixir apps."

  def project do
    [
      app: :regent_chatgpt,
      version: @version,
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
      deps: deps(),
      aliases: aliases(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger]
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test, precommit: :test]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "README.md",
        "lib",
        "mix.exs"
      ],
      licenses: ["MIT"],
      links: %{
        "Login with ChatGPT" => "https://github.com/opencoredev/login-with-chatgpt",
        "Source" => "https://github.com/regents-ai/regent/tree/main/elixir-utils/chatgpt"
      }
    ]
  end

  defp aliases do
    [
      check: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "test"
      ],
      precommit: ["check"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Start Here": [RegentChatGPT, RegentChatGPT.Config, RegentChatGPT.Error],
        Authentication: [
          RegentChatGPT.Device,
          RegentChatGPT.OAuth,
          RegentChatGPT.PKCE,
          RegentChatGPT.Token,
          RegentChatGPT.JWT
        ],
        Codex: [RegentChatGPT.Codex],
        Support: [
          RegentChatGPT.DeviceCode,
          RegentChatGPT.HTTP,
          RegentChatGPT.Redactor,
          RegentChatGPT.TokenSet,
          RegentChatGPT.User
        ]
      ]
    ]
  end
end

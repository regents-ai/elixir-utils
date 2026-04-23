defmodule XmtpElixirSdk.MixProject do
  use Mix.Project

  @version "0.1.1"
  @description "An Elixir-first XMTP SDK with a minimal browser shim for browser-only runtime concerns."

  def project do
    [
      app: :xmtp_elixir_sdk,
      version: @version,
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:xmtp_compat],
      deps: deps(),
      description: @description,
      package: package(),
      aliases: aliases(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [
      preferred_envs: [check: :test, precommit: :test]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.13"},
      {:phoenix_pubsub, "~> 2.2"},
      {:keccak_ex, "~> 0.4.2"},
      {:ex_secp256k1, "~> 0.8.0"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
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

  defp package do
    [
      name: "xmtp_elixir_sdk",
      licenses: ["MIT"],
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        "compat_ebin",
        "lib",
        "readme-assets",
        "mix.exs"
      ],
      links: %{
        "XMTP" => "https://xmtp.org",
        "Upstream Browser SDK" => "https://github.com/xmtp/xmtp-js/tree/main/sdks/browser-sdk"
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

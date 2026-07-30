defmodule XmtpElixirSdk.MixProject do
  use Mix.Project

  @version "0.1.2"
  @description "An Elixir-first XMTP SDK backed by the official Rust XMTP SDK."

  def project do
    [
      app: :xmtp_elixir_sdk,
      version: @version,
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:xmtp_native],
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
      {:jason, "~> 1.4"},
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
        "cmd cargo build --manifest-path native/xmtp_native/Cargo.toml",
        "cmd npm --prefix browser_shim ci",
        "cmd npm --prefix browser_shim test -- --run",
        "cmd npm --prefix browser_shim run typecheck",
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "test --warnings-as-errors"
      ],
      "native.build": ["cmd cargo build --release --manifest-path native/xmtp_native/Cargo.toml"],
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
        "docs",
        "lib",
        "native/xmtp_native/Cargo.toml",
        "native/xmtp_native/Cargo.lock",
        "native/xmtp_native/build.rs",
        "native/xmtp_native/src",
        "priv",
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
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/phoenix-frontend-agent-guide.md",
        "docs/storage-contract.md"
      ]
    ]
  end
end

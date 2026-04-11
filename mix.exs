defmodule XmtpElixirSdk.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "An Elixir-first XMTP SDK with a minimal browser shim for browser-only runtime concerns."

  def project do
    [
      app: :xmtp_elixir_sdk,
      version: @version,
      elixir: "~> 1.19.5",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir, :app],
      deps: deps(),
      description: @description,
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [extra_applications: [:logger]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "xmtp_elixir_sdk",
      licenses: ["MIT"],
      files: [
        ".formatter.exs",
        "LICENSE",
        "README.md",
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
      extras: ["README.md"]
    ]
  end
end

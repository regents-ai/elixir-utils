defmodule RegentMCPEvents.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_mcp_events,
      version: "0.1.0",
      elixir: "~> 1.19.5",
      description: "Durable MCP event delivery and safe signed callbacks for Regent products",
      deps: [{:jason, "~> 1.4"}, {:mint, "~> 1.11"}],
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted"]]
    ]
  end

  def application, do: [extra_applications: [:crypto, :ssl]]
end

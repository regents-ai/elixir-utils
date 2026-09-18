defmodule RegentAgentAccess.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_agent_access,
      version: "0.1.0",
      elixir: "~> 1.19.5",
      description:
        "Accept negotiation, Vary merging and recovery responses for Regent Phoenix products",
      deps: [{:phoenix, "~> 1.8"}],
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted"]]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end

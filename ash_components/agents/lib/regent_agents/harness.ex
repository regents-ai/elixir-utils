defmodule RegentAgents.Harness do
  @moduledoc "What an agent runs on. `other` is for anything not listed."

  use Ash.Type.Enum,
    values: [
      hermes: [label: "Hermes"],
      grok_bot: [label: "Grok Bot"],
      muse: [label: "Muse"],
      openclaw: [label: "OpenClaw"],
      nemoclaw: [label: "NemoClaw"],
      ironclaw: [label: "IronClaw"],
      pi: [label: "Pi"],
      claude_code: [label: "Claude Code"],
      codex: [label: "Codex"],
      chatgpt: [label: "ChatGPT"],
      claude: [label: "Claude"],
      cursor: [label: "Cursor"],
      gemini_cli: [label: "Gemini CLI"],
      dots: [label: "Dots"],
      other: [label: "Other"]
    ]

  @doc """
  The ten agents the side panel offers, in its order: any agent, OpenAI's Codex,
  Grok Bot, Muse, Hermes, Dots, IronClaw, OpenClaw, Claude Code and Pi. Every
  site offers all ten (`RegentAgents.PairingMessage` has their words). An agent
  on any other harness, NemoClaw among them, pairs as any agent.
  """
  def featured,
    do: [
      :other,
      :codex,
      :grok_bot,
      :muse,
      :hermes,
      :dots,
      :ironclaw,
      :openclaw,
      :claude_code,
      :pi
    ]

  @doc "The connected apps: they pair through a site's hosted connection, not a key of their own."
  def connected_apps, do: [:chatgpt, :claude]

  @doc """
  The agents a site's pairing box offers. ChatGPT and Claude pair through the
  site's hosted connection and its identity tools, which only some sites serve,
  so they are offered only where the site sets
  `config :regent_agents, hosted_pairing: true`.
  """
  def offered do
    if Application.get_env(:regent_agents, :hosted_pairing, false),
      do: values(),
      else: values() -- connected_apps()
  end
end

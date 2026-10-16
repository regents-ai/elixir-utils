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
      cursor: [label: "Cursor"],
      gemini_cli: [label: "Gemini CLI"],
      dots: [label: "Dots"],
      other: [label: "Other"]
    ]

  @doc """
  The five agents the side panel offers, in its order: any agent, then OpenAI's
  Codex, Grok Bot, Muse and Hermes. Every site offers all five, and each has its
  own pairing message (`RegentAgents.PairingMessage`).
  """
  def featured, do: [:other, :codex, :grok_bot, :muse, :hermes]

  @doc """
  The agents a site's pairing box offers. ChatGPT pairs through a connected plugin
  and identity tools that only some sites serve, so it is offered only where the
  site sets `config :regent_agents, chatgpt_pairing: true`.
  """
  def offered do
    if Application.get_env(:regent_agents, :chatgpt_pairing, false),
      do: values(),
      else: values() -- [:chatgpt]
  end
end

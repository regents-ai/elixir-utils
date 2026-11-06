defmodule RegentAgents.PairingMessage do
  @moduledoc """
  What a person pastes to their agent to pair it, in three lines: that the
  account is their Regents Labs account and which site they pair it on, the
  pairing code, and the agent's own skill on that site, whose "Pair with a
  person's account" steps say the rest. ChatGPT and Claude, the hosted
  runtimes, are told to pair through the site's hosted connection instead.

  A pairing link that names the page the agent should begin on (`start`, a path
  on the same site) ends the message by sending it there once it is paired.
  """

  @doc """
  The message for `code`, made on the site at `origin` (its address with no
  trailing slash), for an agent on `harness`. `:start` is the page the agent
  begins on once paired, always the last line.
  """
  @spec text(String.t(), String.t(), RegentAgents.Harness.t() | nil, start: String.t() | nil) ::
          String.t()
  def text(code, origin, harness, opts \\ []) do
    [pairing(code, origin, harness), start_line(origin, opts[:start])]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @doc """
  The agent's skill on the site at `origin`: `/agents/SLUG/skill.md`, its
  harness with `-` for `_`. Every site has a skill for each of the ten agents in
  `RegentAgents.Harness.featured/0`; an agent on any other harness, or on none
  named, pairs as any agent and gets `other`'s.
  """
  def skill_url(origin, harness), do: "#{origin}/agents/#{slug(harness)}/skill.md"

  defp slug(harness) do
    if harness in RegentAgents.Harness.featured(),
      do: harness |> Atom.to_string() |> String.replace("_", "-"),
      else: "other"
  end

  defp pairing(code, origin, :chatgpt), do: hosted(code, origin, "ChatGPT", "plugin", :chatgpt)
  defp pairing(code, origin, :claude), do: hosted(code, origin, "Claude", "connector", :claude)

  defp pairing(code, origin, harness) do
    """
    Pair with my Regents Labs account on #{URI.parse(origin).host}
    Pairing code: #{code}
    Follow the "Pair with a person's account" steps in #{skill_url(origin, harness)}\
    """
  end

  defp hosted(code, origin, app, door, harness) do
    """
    Connect #{app} to my existing Regents Labs account on #{URI.parse(origin).host} using this site's #{door}.
    Use register_identity, then get_identity. Reuse this connection across chats.
    If pairing is needed, I approve pair_identity with this one-use code, the name #{app} and the harness #{harness}.
    Pairing code: #{code}
    My Agents page is #{origin}/account/agents#account-pairing. Never repeat this code in your reply.
    If the #{door}'s identity tools are unavailable, report that setup is needed.\
    """
  end

  defp start_line(_origin, nil), do: nil
  defp start_line(origin, start), do: "Once paired, start at #{origin}#{start}"
end

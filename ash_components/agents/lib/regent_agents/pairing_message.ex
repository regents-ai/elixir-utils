defmodule RegentAgents.PairingMessage do
  @moduledoc """
  What a person pastes to their agent to pair it: that the account is their
  Regents Labs account and which site they pair it on, the pairing code, where
  the pairing steps are and how long the code lasts. A pairing link that names the
  page the agent should begin on (`start`, a path on the same site) adds a line
  sending it there once it is paired. Codex, Grok Bot, Hermes and
  Muse each get one more line for the mistake that agent most often makes on its
  first pairing. Muse runs where siwa.regents.sh may not answer, so its line
  names the SIWA service's other address.
  """

  @doc """
  The message for `code`, made on the site at `origin` (its address with no
  trailing slash), for an agent on `harness`, and the page it begins on once
  paired when `start` names one.
  """
  @spec text(String.t(), String.t(), RegentAgents.Harness.t() | nil, String.t() | nil) ::
          String.t()
  def text(code, origin, harness, start \\ nil)

  def text(code, origin, :chatgpt, start) do
    """
    Connect ChatGPT to my existing Regents Labs account on #{URI.parse(origin).host} using this site's connected plugin.
    Use register_identity, then get_identity. Reuse this connection across chats.
    If pairing is needed, I approve pair_identity with this one-use code and the name ChatGPT.
    Pairing code: #{code}
    My account page is #{origin}/account. Never repeat this code in your reply.
    If the plugin's identity tools are unavailable, report that setup is needed.
    """ <> start_line(origin, start, "\n")
  end

  def text(code, origin, harness, start) do
    """
    Pair with my Regents Labs account on #{URI.parse(origin).host}
    Pairing code: #{code}
    Follow the "Pair with a person's account" steps at #{origin}/llms.txt
    The code works once, for ten minutes. If it fails, ask me for a new one.\
    """ <> first_pairing(harness) <> start_line(origin, start, "")
  end

  defp start_line(_origin, nil, _end), do: ""

  defp start_line(origin, start, line_end),
    do: "\nOnce paired, start at #{origin}#{start}" <> line_end

  defp first_pairing(:codex),
    do:
      "\nIf your sandbox blocks the network, ask me to allow it for this step. " <>
        "Keep pair.json in your home folder, never in this project."

  defp first_pairing(:grok_bot),
    do:
      "\nNever put this code in a public reply or post. " <>
        "Pair from your own tools, then tell me it worked."

  defp first_pairing(:hermes),
    do: "\nKeep the key you pair with and use it in every chat. Never make a second one."

  defp first_pairing(:muse),
    do:
      "\nIf siwa.regents.sh doesn't answer from your host, set " <>
        "SIWA_BROKER=https://siwa-server.fly.dev and try again."

  defp first_pairing(_harness), do: ""
end

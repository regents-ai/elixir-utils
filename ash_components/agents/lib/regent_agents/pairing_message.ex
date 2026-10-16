defmodule RegentAgents.PairingMessage do
  @moduledoc """
  What a person pastes to their agent to pair it: the site's name, the pairing
  code, where the pairing steps are and how long the code lasts. Codex, Grok Bot,
  Hermes and Muse each get one more line for the mistake that agent most often
  makes on its first pairing. Muse runs where siwa.regents.sh
  may not answer, so its line names the SIWA service's other address.
  """

  @doc """
  The message for `code`, made on the site called `site` at `origin` (its
  address with no trailing slash), for an agent on `harness`.
  """
  @spec text(String.t(), String.t(), String.t(), RegentAgents.Harness.t() | nil) :: String.t()
  def text(code, site, origin, :chatgpt) do
    """
    Connect ChatGPT to my existing #{site} account using this site's connected plugin.
    Use register_identity, then get_identity. Reuse this connection across chats.
    If pairing is needed, I approve pair_identity with this one-use code and the name ChatGPT.
    Pairing code: #{code}
    My account page is #{origin}/account. Never repeat this code in your reply.
    If the plugin's identity tools are unavailable, report that setup is needed.
    """
  end

  def text(code, site, origin, harness) do
    """
    Pair with my #{site} account.
    Pairing code: #{code}
    Follow the "Pair with a person's account" steps at #{origin}/llms.txt
    The code works once, for ten minutes. If it fails, ask me for a new one.\
    """ <> first_pairing(harness)
  end

  defp first_pairing(:codex),
    do:
      "\nIf your sandbox blocks the network, ask me to allow it for this step. " <>
        "Keep pair.json in your home folder, never in this project."

  defp first_pairing(:grok_bot),
    do:
      "\nNever put this code in a public reply or post. " <>
        "Pair from your own tools, then tell me it worked."

  defp first_pairing(:hermes),
    do: "\nKeep the key regents-cli makes and use it in every chat. Never make a second one."

  defp first_pairing(:muse),
    do:
      "\nIf siwa.regents.sh doesn't answer from your host, set " <>
        "SIWA_BROKER=https://siwa-server.fly.dev and try again."

  defp first_pairing(_harness), do: ""
end

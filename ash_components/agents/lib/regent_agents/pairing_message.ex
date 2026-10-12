defmodule RegentAgents.PairingMessage do
  @moduledoc """
  What a person pastes to their agent to pair it: the site's name, the pairing
  code and where the pairing steps are. Muse runs where siwa.regents.sh may not
  answer, so its message also names the SIWA service's other address.
  """

  @doc """
  The message for `code`, made on the site called `site` at `origin` (its
  address with no trailing slash), for an agent on `harness`.
  """
  @spec text(String.t(), String.t(), String.t(), RegentAgents.Harness.t() | nil) :: String.t()
  def text(code, site, origin, :muse) do
    text(code, site, origin, nil) <>
      "\nIf siwa.regents.sh doesn't answer from your host, set " <>
      "SIWA_BROKER=https://siwa-server.fly.dev and try again."
  end

  def text(code, site, origin, _harness) do
    """
    Pair with my #{site} account.
    Pairing code: #{code}
    Follow the "Pair with a person's account" steps at #{origin}/llms.txt\
    """
  end
end

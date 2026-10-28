defmodule RegentAgents.Broker do
  @moduledoc """
  Sends a signed agent request to the SIWA service to be verified, with this
  site's own verify key, from
  `config :regent_agents, siwa: [url: ..., audience: ..., verify_key: ...]`. The
  key names the audience the SIWA service checks the request for.
  """
  @behaviour Siwa.AgentAuthPlug.Client

  @impl true
  def verify_http_request(payload) do
    Siwa.AgentAuthPlug.BrokerClient.verify_http_request(payload,
      http: __MODULE__,
      base_url: Keyword.fetch!(config(), :url),
      site_key: Keyword.fetch!(config(), :verify_key),
      connect_timeout_ms: 2_000,
      receive_timeout_ms: 5_000
    )
  end

  @doc "This site's SIWA audience."
  @spec audience() :: String.t()
  def audience, do: Keyword.fetch!(config(), :audience)

  # Every request to the SIWA service goes through here. Verification spends
  # replay state, and both verification and the activity read carry one of this
  # site's keys, so neither retries nor follows a redirect.
  @doc false
  def request(options) do
    options
    |> Keyword.merge(Application.get_env(:regent_agents, :req_options, []))
    |> Keyword.merge(retry: false, redirect: false)
    |> Req.request()
  end

  defp config, do: Application.fetch_env!(:regent_agents, :siwa)
end

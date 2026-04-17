defmodule Siwa.TBA do
  def account_key(agent_registry, agent_id, implementation \\ "erc6551") do
    %{agent_registry: agent_registry, agent_id: agent_id, implementation: implementation}
  end

  def matches?(account, agent_registry, agent_id) do
    account.agent_registry == agent_registry and account.agent_id == agent_id
  end
end

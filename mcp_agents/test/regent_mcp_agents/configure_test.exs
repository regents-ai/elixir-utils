defmodule RegentMCPAgents.ConfigureTest do
  # A site switches hosted identity on only with a site name as its audience, at
  # least one hosted runtime to offer and refusal words of a sensible length.
  use RegentMCPAgents.Case

  setup do
    config = Application.fetch_env!(:regent_mcp_agents, :config)
    on_exit(fn -> Application.put_env(:regent_mcp_agents, :config, config) end)
    %{config: config}
  end

  test "Keyfleet's settings with Claude offered are accepted" do
    assert RegentMCPAgents.configure!() == :ok
    assert RegentMCPAgents.hosted_names() == ["claude"]
  end

  test "a site name switches hosted identity on; an audience that is not one cannot", %{
    config: config
  } do
    for audience <- ["patchbay", "ash-template", "chainagent"] do
      Application.put_env(:regent_mcp_agents, :config, Keyword.put(config, :audience, audience))
      assert RegentMCPAgents.configure!() == :ok
    end

    for audience <- ["regents.sh", "Regents", "https://regents.sh", "a", "", nil] do
      Application.put_env(:regent_mcp_agents, :config, Keyword.put(config, :audience, audience))
      assert_raise ArgumentError, &RegentMCPAgents.configure!/0
    end
  end

  test "a site offering no hosted runtime cannot switch hosted identity on" do
    Application.put_env(:regent_agents, :hosted_pairing, [])
    assert_raise ArgumentError, ~r/hosted_pairing/, &RegentMCPAgents.configure!/0
  end

  test "refusal words are 1 to 500 bytes", %{config: config} do
    for refusal <- ["", String.duplicate("a", 501)] do
      Application.put_env(:regent_mcp_agents, :config, Keyword.put(config, :refusal, refusal))
      assert_raise ArgumentError, ~r/refusal words/, &RegentMCPAgents.configure!/0
    end

    Application.put_env(:regent_mcp_agents, :config, Keyword.put(config, :refusal, "Ask again."))
    assert RegentMCPAgents.configure!() == :ok
    assert RegentMCPAgents.refusal_text() == "Ask again."
  end
end

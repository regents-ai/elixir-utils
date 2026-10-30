defmodule RegentAgents.AgentPictureTest do
  use RegentAgents.Case, async: true

  @wallet "0x2222222222222222222222222222222222222222"
  @sibling_wallet "0x3333333333333333333333333333333333333333"
  @webp <<"RIFF", 12::little-32, "WEBPVP8 ", 0::32>>

  setup do
    owner = person("pictures")

    {:ok, agent} =
      RegentAgents.pair_agent(code!(owner), "Ada", :claude_code, actor: %Agent{wallet: @wallet})

    {:ok, sibling} =
      RegentAgents.pair_agent(code!(owner), "Bea", :codex, actor: %Agent{wallet: @sibling_wallet})

    %{owner: owner, agent: agent, sibling: sibling}
  end

  # The site's paired agent, as its signed-request plug builds it.
  defp acting(agent),
    do: %{
      role: :agent,
      pairing_id: agent.id,
      privy_user_id: agent.privy_user_id,
      wallet_address: agent.wallet
    }

  test "a paired agent sets, replaces and removes its own picture", %{agent: agent} do
    assert {:ok, _picture} =
             RegentAgents.set_own_agent_picture(agent.id, @webp, actor: acting(agent))

    assert {:ok, %{bytes: @webp}} = RegentAgents.agent_picture(@wallet)

    newer = @webp <> <<1>>

    assert {:ok, _picture} =
             RegentAgents.set_own_agent_picture(agent.id, newer, actor: acting(agent))

    assert {:ok, %{bytes: ^newer}} = RegentAgents.agent_picture(@wallet)

    assert :ok = RegentAgents.remove_own_agent_picture(agent.id, actor: acting(agent))
    assert {:ok, nil} = RegentAgents.agent_picture(@wallet)
  end

  test "an agent never changes another agent's picture, even one of the same person",
       %{owner: owner, agent: agent, sibling: sibling} do
    assert {:error, %Ash.Error.Forbidden{}} =
             RegentAgents.set_own_agent_picture(sibling.id, @webp, actor: acting(agent))

    assert {:ok, _picture} = RegentAgents.set_agent_picture(sibling.id, @webp, actor: owner)

    assert {:error, %Ash.Error.Forbidden{}} =
             RegentAgents.remove_own_agent_picture(sibling.id, actor: acting(agent))

    assert {:ok, %{bytes: @webp}} = RegentAgents.agent_picture(@sibling_wallet)
  end

  test "an agent's old pairing changes nothing once it has paired again",
       %{owner: owner, agent: agent} do
    {:ok, mine} = RegentAgents.get_my_agent(agent.id, actor: owner)
    RegentAgents.unpair_agent!(mine, actor: owner)

    {:ok, again} =
      RegentAgents.pair_agent(code!(owner), "Ada", :claude_code, actor: %Agent{wallet: @wallet})

    assert {:ok, _picture} =
             RegentAgents.set_own_agent_picture(again.id, @webp, actor: acting(again))

    assert {:error, %Ash.Error.Forbidden{}} =
             RegentAgents.set_own_agent_picture(again.id, @webp <> <<1>>, actor: acting(agent))

    assert {:error, %Ash.Error.Forbidden{}} =
             RegentAgents.remove_own_agent_picture(again.id, actor: acting(agent))

    assert {:ok, %{bytes: @webp}} = RegentAgents.agent_picture(@wallet)
  end
end

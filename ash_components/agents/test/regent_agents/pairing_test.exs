defmodule RegentAgents.PairingTest do
  use RegentAgents.Case, async: true

  alias RegentAgents.PairingCode

  @wallet "0x2222222222222222222222222222222222222222"
  @other_wallet "0x3333333333333333333333333333333333333333"

  test "a code is short-lived and stored only as a hash, and a new one leaves the earlier one working" do
    owner = person("code")

    assert {:ok, issued} = RegentAgents.issue_pairing_code(actor: owner)
    assert byte_size(issued.code) == 24
    assert DateTime.diff(issued.expires_at, issued.issued_at) == 600

    stored =
      PairingCode
      |> Ash.Query.for_read(:by_code_hash, %{code_hash: PairingCode.hash(issued.code)},
        actor: %Agent{wallet: @wallet}
      )
      |> Ash.read_one!()

    assert stored.privy_user_id == owner.privy_user_id
    refute stored.code_hash == issued.code

    assert {:ok, newer} = RegentAgents.issue_pairing_code(actor: owner)
    refute newer.code == issued.code

    assert {:ok, _agent} =
             RegentAgents.pair_agent(issued.code, "Earlier", :hermes,
               actor: %Agent{wallet: @wallet}
             )

    assert {:ok, _agent} =
             RegentAgents.pair_agent(newer.code, "Newer", :muse,
               actor: %Agent{wallet: @other_wallet}
             )
  end

  test "a valid code pairs the signing agent with the person who made it, once" do
    owner = person("happy")
    code = code!(owner)

    assert {:ok, agent} =
             RegentAgents.pair_agent(code, "  Sol  ", :claude_code,
               actor: %Agent{wallet: @wallet}
             )

    assert %{
             privy_user_id: "did:privy:happy",
             wallet: @wallet,
             name: "Sol",
             harness: :claude_code
           } =
             agent

    assert {:error, _used} =
             RegentAgents.pair_agent(code, "Again", :muse, actor: %Agent{wallet: @other_wallet})

    assert {:ok, [%{wallet: @wallet}]} = RegentAgents.list_my_agents(actor: owner)
  end

  test "an expired code pairs nobody" do
    owner = person("late")
    code = code!(owner)
    age_code!(owner, 600)

    assert {:error, _expired} =
             RegentAgents.pair_agent(code, "Late", :pi, actor: %Agent{wallet: @wallet})

    assert {:ok, []} = RegentAgents.list_my_agents(actor: owner)
  end

  test "one key belongs to one person" do
    first = person("first")
    second = person("second")
    first_code = code!(first)
    second_code = code!(second)

    assert {:ok, _agent} =
             RegentAgents.pair_agent(first_code, "First", :grok_bot,
               actor: %Agent{wallet: @wallet}
             )

    assert {:error, _taken} =
             RegentAgents.pair_agent(second_code, "Second", :grok_bot,
               actor: %Agent{wallet: @wallet}
             )

    assert {:ok, []} = RegentAgents.list_my_agents(actor: second)
  end

  test "checking in marks the agent's last contact, and a stranger is not paired" do
    owner = person("check")
    paired = RegentAgents.pair_agent!(code!(owner), "Muse", :muse, actor: %Agent{wallet: @wallet})

    assert {:ok, checked_in} = RegentAgents.check_in_agent(actor: %Agent{wallet: @wallet})
    assert checked_in.id == paired.id
    assert DateTime.compare(checked_in.last_contact_at, paired.last_contact_at) == :gt

    assert {:error, _not_paired} =
             RegentAgents.check_in_agent(actor: %Agent{wallet: @other_wallet})
  end

  test "only the owner sees or unpairs an agent" do
    owner = person("owner")
    other = person("other")

    agent =
      RegentAgents.pair_agent!(code!(owner), "Hermes", :hermes, actor: %Agent{wallet: @wallet})

    assert {:ok, []} = RegentAgents.list_my_agents(actor: other)
    assert {:ok, nil} = RegentAgents.get_my_agent(agent.id, actor: other)

    assert {:error, %Ash.Error.Forbidden{}} = RegentAgents.unpair_agent(agent, actor: other)

    assert :ok = RegentAgents.unpair_agent(agent, actor: owner)
    assert {:ok, []} = RegentAgents.list_my_agents(actor: owner)
    assert {:ok, nil} = RegentAgents.current_pairing(actor: %Agent{wallet: @wallet})

    assert %{rows: [[revoked_at]]} =
             RegentAgents.TestRepo.query!(
               "SELECT revoked_at FROM regent_agents.pairing_history WHERE id = $1",
               [Ecto.UUID.dump!(agent.id)]
             )

    assert revoked_at != nil

    assert {:ok, next} =
             RegentAgents.pair_agent(code!(owner), "Again", :hermes,
               actor: %Agent{wallet: @wallet}
             )

    refute next.id == agent.id

    # Deployed older sites read by wallet without a revocation predicate and
    # unpair with DELETE. Both must retain their semantics and episode evidence.
    assert %{rows: [[id]]} =
             RegentAgents.TestRepo.query!(
               "SELECT id FROM regent_agents.paired_agents WHERE wallet = $1",
               [@wallet]
             )

    assert Ecto.UUID.load!(id) == next.id

    RegentAgents.TestRepo.query!(
      "DELETE FROM regent_agents.paired_agents WHERE id = $1",
      [id]
    )

    assert %{rows: [[at]]} =
             RegentAgents.TestRepo.query!(
               "SELECT revoked_at FROM regent_agents.pairing_history WHERE id = $1",
               [id]
             )

    assert at != nil
    assert {:ok, nil} = RegentAgents.current_pairing(actor: %Agent{wallet: @wallet})
  end

  test "a person's agents need a signed-in person" do
    assert {:error, _error} = RegentAgents.list_my_agents(actor: %Agent{wallet: @wallet})
    assert {:error, _error} = RegentAgents.issue_pairing_code(actor: %Agent{wallet: @wallet})
  end
end

defmodule RegentAgents.PairingLimitTest do
  use ExUnit.Case, async: false
  alias RegentAgents.{Agent, Person, TestRepo}

  test "concurrent hundredth pairing succeeds once and the rejected code remains unused" do
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual) end)
    owner = %Person{privy_user_id: "did:privy:limit-" <> Ecto.UUID.generate()}
    prefix = Base.encode16(:crypto.strong_rand_bytes(18), case: :lower)

    TestRepo.query!(
      """
      INSERT INTO regent_agents.paired_agents (id, privy_user_id, wallet, name, harness, paired_at, last_contact_at)
      SELECT gen_random_uuid(), $1, '0x' || $2 || lpad(to_hex(n), 4, '0'), 'Limit', 'codex', now(), now()
      FROM generate_series(1, 99) AS n
      """,
      [owner.privy_user_id, prefix]
    )

    requests =
      for _ <- 1..2 do
        {RegentAgents.issue_pairing_code!(actor: owner).code,
         %Agent{wallet: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)}}
      end

    results =
      Task.async_stream(
        requests,
        fn {code, actor} ->
          {code, RegentAgents.pair_agent(code, "Hundred", :codex, actor: actor)}
        end,
        max_concurrency: 2
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, fn {_, result} -> match?({:ok, _}, result) end) == 1
    assert length(RegentAgents.list_my_agents!(actor: owner)) == 100
    {unused, _} = Enum.find(results, fn {_, result} -> match?({:error, _}, result) end)

    assert %{rows: [[nil]]} =
             TestRepo.query!(
               "SELECT used_at FROM regent_agents.pairing_codes WHERE code_hash = $1",
               [RegentAgents.PairingCode.hash(unused)]
             )
  end
end

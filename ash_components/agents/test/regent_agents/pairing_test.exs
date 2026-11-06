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

  # Autolaunch, 27 Oct 2026: with two codes on screen, the pairing box named the
  # agent under the wrong one.
  test "each used code names the agent it paired, and only to the person who made it" do
    owner = person("two-codes")
    first = code!(owner)
    second = code!(owner)
    third = code!(owner)

    assert {:ok, %{id: first_agent}} =
             RegentAgents.pair_agent(first, "First", :claude_code, actor: %Agent{wallet: @wallet})

    assert {:ok, %{id: third_agent}} =
             RegentAgents.pair_agent(third, "Third", :codex, actor: %Agent{wallet: @other_wallet})

    assert {:ok, paired} = RegentAgents.agents_paired_with([first, second, third], actor: owner)
    assert %{^first => %{id: ^first_agent}, ^third => %{id: ^third_agent}} = paired
    refute Map.has_key?(paired, second)

    assert RegentAgents.agents_paired_with([first, third], actor: person("someone-else")) ==
             {:ok, %{}}

    assert {:error, _not_a_person} =
             RegentAgents.agents_paired_with([first], actor: %Agent{wallet: @wallet})
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

    assert {:ok, checked_in} =
             RegentAgents.check_in_agent(owner.privy_user_id, actor: %Agent{wallet: @wallet})

    assert checked_in.id == paired.id
    assert DateTime.compare(checked_in.last_contact_at, paired.last_contact_at) == :gt

    assert {:error, _not_paired} =
             RegentAgents.check_in_agent(owner.privy_user_id,
               actor: %Agent{wallet: @other_wallet}
             )
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

  # Invariant: only the agent's own person renames it, a name holding a hidden
  # character is refused, and the kept history follows the new name.
  test "only the owner renames an agent, and its history keeps the new name" do
    owner = person("namer")
    other = person("not-namer")

    agent =
      RegentAgents.pair_agent!(code!(owner), "Hermes", :hermes, actor: %Agent{wallet: @wallet})

    assert {:error, %Ash.Error.Forbidden{}} =
             RegentAgents.rename_agent(agent, "Taken", actor: other)

    assert {:error, %Ash.Error.Forbidden{}} =
             RegentAgents.rename_agent(agent, "Self", actor: %Agent{wallet: @wallet})

    for name <- ["  ", String.duplicate("a", 81), "Night\u202EShift", "Night\u200BShift"] do
      assert {:error, %Ash.Error.Invalid{}} = RegentAgents.rename_agent(agent, name, actor: owner)
    end

    assert {:ok, %{name: "Night Shift 👩\u200D💻"}} =
             RegentAgents.rename_agent(agent, "  Night Shift 👩\u200D💻 ", actor: owner)

    assert {:ok, %{name: "Night Shift 👩\u200D💻"}} =
             RegentAgents.get_my_agent(agent.id, actor: owner)

    assert %{rows: [["Night Shift 👩\u200D💻"]]} =
             RegentAgents.TestRepo.query!(
               "SELECT name FROM regent_agents.pairing_history WHERE id = $1",
               [Ecto.UUID.dump!(agent.id)]
             )
  end

  test "a pairing tells the site once, inside its own transaction, naming its history row" do
    owner = person("told")
    code = code!(owner)

    assert {:ok, agent} =
             RegentAgents.pair_agent(code, "Told", :codex, actor: %Agent{wallet: @wallet})

    assert_received {:paired, id, "did:privy:told", true} when id == agent.id

    assert %{rows: [[_row]]} =
             RegentAgents.TestRepo.query!(
               "SELECT 1 FROM regent_agents.pairing_history WHERE id = $1 AND privy_user_id = $2",
               [Ecto.UUID.dump!(agent.id), owner.privy_user_id]
             )

    assert {:error, _used} =
             RegentAgents.pair_agent(code, "Again", :muse, actor: %Agent{wallet: @other_wallet})

    refute_received {:paired, _, _, _}
  end

  # Invariant: sites read a pairing's owner, wallet and dates through these two
  # calls, and an unpaired pairing is still found, marked revoked.
  test "a pairing's history is read by its id and by its person, unpaired ones included" do
    owner = person("kept")

    first =
      RegentAgents.pair_agent!(code!(owner), "First", :hermes, actor: %Agent{wallet: @wallet})

    RegentAgents.pair_agent!(code!(person("someone-else")), "Theirs", :codex,
      actor: %Agent{wallet: @other_wallet}
    )

    assert {:ok, %{revoked_at: nil} = kept} = RegentAgents.pairing_history(first.id)

    assert %{id: id, privy_user_id: "did:privy:kept", wallet: @wallet, name: "First"} = kept
    assert id == first.id
    assert %DateTime{} = kept.paired_at

    :ok = RegentAgents.unpair_agent(first, actor: owner)

    second =
      RegentAgents.pair_agent!(code!(owner), "Second", :muse, actor: %Agent{wallet: @wallet})

    assert {:ok, %{revoked_at: %DateTime{}}} = RegentAgents.pairing_history(first.id)

    assert {:ok, [%{id: ^id, revoked_at: %DateTime{}}, %{name: "Second", revoked_at: nil} = now]} =
             RegentAgents.pairing_histories(owner.privy_user_id)

    assert now.id == second.id
    assert {:ok, nil} = RegentAgents.pairing_history(Ecto.UUID.generate())
    assert {:ok, []} = RegentAgents.pairing_histories("did:privy:nobody")
  end

  # Invariant: a wallet's action at a moment belongs to the one pairing that held
  # the wallet then, never to a later or current pairing, and never to a guess
  # between two.
  test "a wallet's pairing at a moment is the one pairing holding it then" do
    owner = person("at")

    first =
      RegentAgents.pair_agent!(code!(owner), "Then", :hermes, actor: %Agent{wallet: @wallet})

    {:ok, %{paired_at: paired_at}} = RegentAgents.pairing_history(first.id)

    assert {:ok, %{id: id, privy_user_id: "did:privy:at"}} =
             RegentAgents.pairing_at(@wallet, paired_at)

    assert id == first.id

    before = DateTime.add(paired_at, -1, :microsecond)
    assert {:error, :unknown_owner} = RegentAgents.pairing_at(@wallet, before)
    assert {:error, :unknown_owner} = RegentAgents.pairing_at(@other_wallet, paired_at)

    :ok = RegentAgents.unpair_agent(first, actor: owner)
    {:ok, %{revoked_at: revoked_at}} = RegentAgents.pairing_history(first.id)
    assert {:error, :unknown_owner} = RegentAgents.pairing_at(@wallet, revoked_at)

    assert {:ok, %{id: ^id}} =
             RegentAgents.pairing_at(@wallet, DateTime.add(revoked_at, -1, :microsecond))

    RegentAgents.TestRepo.query!(
      """
      INSERT INTO regent_agents.pairing_history
        (id, privy_user_id, wallet, name, harness, paired_at, last_contact_at)
      VALUES ($1, 'did:privy:overlap', $2, 'Overlap', 'codex', $3, $3)
      """,
      [Ecto.UUID.bingenerate(), @wallet, DateTime.add(paired_at, -1, :hour)]
    )

    assert {:error, :unknown_owner} = RegentAgents.pairing_at(@wallet, paired_at)
  end

  # Invariant: what a person already had at a moment is their earliest pairing from
  # before it that is still paired, once per person, whatever came later.
  test "the pairings held from before a moment, one per person" do
    at = ~U[2026-01-10 00:00:00.000000Z]
    did = "did:privy:held-" <> Ecto.UUID.generate()
    other = "did:privy:held-other-" <> Ecto.UUID.generate()

    history = fn privy_user_id, paired_at, revoked_at ->
      id = Ecto.UUID.generate()

      RegentAgents.TestRepo.query!(
        """
        INSERT INTO regent_agents.pairing_history
          (id, privy_user_id, wallet, name, harness, paired_at, last_contact_at, revoked_at)
        VALUES ($1, $2, $3, 'Held', 'codex', $4, $4, $5)
        """,
        [
          Ecto.UUID.dump!(id),
          privy_user_id,
          "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower),
          paired_at,
          revoked_at
        ]
      )

      id
    end

    _unpaired = history.(did, ~U[2026-01-01 00:00:00.000000Z], ~U[2026-01-02 00:00:00.000000Z])
    held = history.(did, ~U[2026-01-03 00:00:00.000000Z], nil)
    _later = history.(did, ~U[2026-01-05 00:00:00.000000Z], nil)
    _after = history.(other, ~U[2026-01-11 00:00:00.000000Z], nil)

    assert {:ok, pairings} = RegentAgents.pairings_held_from_before(at)
    assert [%{id: ^held}] = Enum.filter(pairings, &(&1.privy_user_id in [did, other]))
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
    {unused, refused} = Enum.find(results, fn {_, result} -> match?({:error, _}, result) end)

    # The refusal keeps its kind through the rolled-back transaction, so the
    # agent hears `agent_limit`.
    assert {:error, %Ash.Error.Invalid{errors: [%RegentAgents.PairedAgent.AgentLimit{}]}} =
             refused

    assert %{rows: [[nil]]} =
             TestRepo.query!(
               "SELECT used_at FROM regent_agents.pairing_codes WHERE code_hash = $1",
               [RegentAgents.PairingCode.hash(unused)]
             )
  end
end

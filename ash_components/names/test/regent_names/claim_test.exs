defmodule RegentNames.ClaimTest do
  @moduledoc """
  A free claim writes two protected tables. Invariants: a name is recorded only
  together with one free claim spent on the claimer's own wallet, a refused
  claim changes neither table, and every read shows only the actor's own
  wallets' rows.
  """
  use RegentNames.Case, async: false

  @main "0x7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a"
  @linked "0x7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b"
  @stranger "0x7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c"

  test "a claim records the name for the claimer's wallet and spends one free claim" do
    insert_allowance(String.upcase(@main), 2, 0)

    assert {:ok, claim} = RegentNames.claim_free_name("fresh-name", actor: person([@main]))

    assert claim.ens_fqdn == "fresh-name.regent.eth"
    assert claim.fqdn == "fresh-name.agent.base.eth"
    assert String.downcase(claim.owner_address) == @main
    assert claim.claim_status == "reserved"
    assert claim.is_free
    assert is_nil(claim.tx_hash)
    assert claim.node =~ ~r/^0x[0-9a-f]{64}$/
    assert used(claim.owner_address) == 1

    assert {:ok, %{results: [mine]}} = RegentNames.list_my_claims(actor: person([@main]))
    assert mine.id == claim.id
  end

  test "the main wallet's free claim is spent before a linked wallet's" do
    insert_allowance(@linked, 1, 0)
    insert_allowance(@main, 1, 0)

    actor = person([@main, @linked])
    assert {:ok, first} = RegentNames.claim_free_name("first-name", actor: actor)
    assert {:ok, second} = RegentNames.claim_free_name("second-name", actor: actor)

    assert {first.owner_address, second.owner_address} == {@main, @linked}
    assert {used(@main), used(@linked)} == {1, 1}
  end

  test "a refused claim records nothing and spends nothing" do
    insert_allowance(@main, 1, 0)
    insert_allowance(@stranger, 5, 0)
    insert_claim(7_000_001, @stranger, %{label: "taken", fqdn: "taken.agent.base.eth"})

    # The name is held, the name breaks the rules, the claimer has no free claim
    # (a stranger's is never spent), and nobody is signed in.
    assert {:error, %Ash.Error.Invalid{}} =
             RegentNames.claim_free_name("taken", actor: person([@main]))

    assert {:error, %Ash.Error.Invalid{}} =
             RegentNames.claim_free_name("-Bad", actor: person([@main]))

    assert {:error, %Ash.Error.Invalid{}} =
             RegentNames.claim_free_name("no-allowance", actor: person([@linked]))

    assert {:error, %Ash.Error.Forbidden{}} = RegentNames.claim_free_name("anonymous", actor: nil)

    assert claim_count() == 1
    assert {used(@main), used(@stranger)} == {0, 0}
  end

  test "a wallet's last free claim cannot be spent twice" do
    insert_allowance(@main, 1, 0)

    assert {:ok, _claim} = RegentNames.claim_free_name("only-name", actor: person([@main]))

    assert {:error, %Ash.Error.Invalid{}} =
             RegentNames.claim_free_name("one-more", actor: person([@main]))

    assert claim_count() == 1
    assert used(@main) == 1
  end

  test "an out-of-date copy of a wallet's last free claim is spent once" do
    insert_allowance(@main, 1, 0)
    assert {:ok, [stale]} = RegentNames.list_my_allowances(actor: person([@main]))

    assert {:ok, _spent} = RegentNames.use_free_claim(stale, actor: person([@main]))

    assert {:error, %Ash.Error.Invalid{}} =
             RegentNames.use_free_claim(stale, actor: person([@main]))

    assert used(@main) == 1
  end

  test "a person sees only their own wallets' names and claims left" do
    insert_claim(7_000_001, @main)
    insert_claim(7_000_002, String.upcase(@linked))
    insert_claim(7_000_003, @stranger)
    insert_allowance(@main, 3, 1)
    insert_allowance(@stranger, 9, 0)
    insert_payment_credit(1, @linked)
    insert_payment_credit(2, @linked, %{consumed_at: DateTime.utc_now()})
    insert_payment_credit(3, @stranger)

    actor = person([@main, @linked])
    assert {:ok, %{results: names}} = RegentNames.list_my_claims(actor: actor)
    assert Enum.map(names, & &1.id) == [7_000_001, 7_000_002]
    assert RegentNames.claims_available(actor: actor) == {:ok, %{free: 2, paid: 1}}
  end

  test "a fresh Privy sign-in for the site's own app reads its wallets' names" do
    insert_claim(7_000_001, @main)
    insert_claim(7_000_002, @stranger)

    session = %RegentPrivy.Session{
      app_id: "names-test-app",
      privy_user_id: "did:privy:names",
      session_id: "session",
      wallet_addresses: [@main],
      expires_at: System.system_time(:second) + 60
    }

    assert {:ok, %{results: [mine]}} = RegentNames.list_my_claims(actor: session)
    assert mine.id == 7_000_001

    other_app = %{session | app_id: "another-app"}
    assert {:error, %Ash.Error.Forbidden{}} = RegentNames.list_my_claims(actor: other_app)
  end
end

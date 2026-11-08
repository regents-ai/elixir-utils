defmodule RegentAgents.OpenedAccountTest do
  # Invariant: once a Privy user is recorded as opened by an agent it stays
  # recorded, whatever wallet opens next; only a site's system actor writes or
  # reads the record, never a person or an agent.
  use RegentAgents.Case, async: true

  @system %{role: :system}
  @wallet "0x00000000000000000000000000000000000000aa"
  @moved "0x00000000000000000000000000000000000000bb"

  test "an opening is kept for each Privy user; opening again names its wallet now" do
    RegentAgents.record_opened_account!(@wallet, "did:privy:first", actor: @system)
    RegentAgents.record_opened_account!(@wallet, "did:privy:second", actor: @system)
    RegentAgents.record_opened_account!(@moved, "did:privy:first", actor: @system)

    assert [{"did:privy:first", @moved}, {"did:privy:second", @wallet}] =
             RegentAgents.OpenedAccount
             |> Ash.read!(actor: @system)
             |> Enum.map(&{&1.privy_user_id, &1.wallet})
             |> Enum.sort()
  end

  test "a person or an agent can neither record nor read one" do
    RegentAgents.record_opened_account!(@wallet, "did:privy:agent", actor: @system)

    for actor <- [person("someone"), %Agent{wallet: @wallet}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               RegentAgents.record_opened_account(@wallet, "did:privy:other", actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.read(RegentAgents.OpenedAccount, actor: actor)
    end
  end
end

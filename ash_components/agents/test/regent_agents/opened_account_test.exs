defmodule RegentAgents.OpenedAccountTest do
  # Invariant: one record per agent wallet, written and read only by a site's
  # system actor; a person or an agent can neither write nor read it.
  use RegentAgents.Case, async: true

  @system %{role: :system}
  @wallet "0x00000000000000000000000000000000000000aa"

  test "a site records the account a wallet opened, once per wallet" do
    RegentAgents.record_opened_account!(@wallet, "did:privy:first", actor: @system)
    RegentAgents.record_opened_account!(@wallet, "did:privy:second", actor: @system)

    assert %{privy_user_id: "did:privy:second"} =
             RegentAgents.opened_account!(@wallet, actor: @system)

    assert [_one] = Ash.read!(RegentAgents.OpenedAccount, actor: @system)
  end

  test "a person or an agent can neither record nor read one" do
    RegentAgents.record_opened_account!(@wallet, "did:privy:agent", actor: @system)

    for actor <- [person("someone"), %Agent{wallet: @wallet}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               RegentAgents.record_opened_account(@wallet, "did:privy:other", actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = RegentAgents.opened_account(@wallet, actor: actor)
    end
  end
end

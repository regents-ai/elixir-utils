defmodule RegentCredits.ListenerTest do
  # The notice commits, as it does on a live site, so the listener hears it
  # through the database the way every other site would.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox

  test "a balance change announced on any site reaches this site's pages" do
    privy_user_id = "did:privy:heard-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(RegentCredits.TestPubSub, RegentCredits.topic(privy_user_id))

    Sandbox.unboxed_run(RegentCredits.TestRepo, fn -> RegentCredits.announce(privy_user_id) end)

    assert_receive :credits_changed
    refute_receive :credits_changed
  end
end

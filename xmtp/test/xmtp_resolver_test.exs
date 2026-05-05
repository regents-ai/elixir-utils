defmodule Xmtp.ResolverTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias Xmtp.Resolver

  setup :start_runtime

  setup do
    name = Module.concat(__MODULE__, "Resolver#{System.unique_integer([:positive])}")
    start_supervised!({Resolver, name: name, positive_ttl_ms: 60_000, null_ttl_ms: 60_000})
    {:ok, resolver: name}
  end

  test "resolves registered wallets to inbox ids", %{resolver: resolver} do
    assert {:ok, alice} = create_client("alice")

    assert {:ok, result} = Resolver.resolve_wallet(resolver, alice, alice.identifier.identifier)

    assert result.status == :ready
    assert result.inbox_id == alice.inbox_id
    assert result.can_message?
  end

  test "caches null results for missing wallets", %{resolver: resolver} do
    bob_wallet = identifier("bob").identifier

    assert {:ok, first} = Resolver.resolve_wallet(resolver, current_runtime(), bob_wallet)
    assert first.status == :not_found

    assert {:ok, _bob} = create_client("bob")
    assert {:ok, second} = Resolver.resolve_wallet(resolver, current_runtime(), bob_wallet)
    assert second.status == :not_found
  end

  test "accepts inbox targets for room invites without wallet lookup", %{resolver: resolver} do
    assert {:ok, result} =
             Resolver.resolve_for_room_invite(resolver, current_runtime(), %{
               inbox_id: "inbox-123"
             })

    assert result.status == :ready
    assert result.inbox_id == "inbox-123"
    assert result.can_message?
  end
end

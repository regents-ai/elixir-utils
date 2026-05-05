defmodule Xmtp.MetadataProfileTest do
  use ExUnit.Case, async: true

  alias Xmtp.Metadata.GroupAppData
  alias Xmtp.Metadata.Profile

  test "profile metadata round-trips through the Regent codec" do
    attrs = %{
      product: :techtree,
      principal_type: :agent,
      principal_id: "agent-1",
      display_name: "Review Agent",
      wallet_address: "0xABC0000000000000000000000000000000000001",
      overlays: %{node_id: "node-1"}
    }

    assert {:ok, encoded} = Profile.encode_regent_profile(attrs)
    assert {:ok, decoded} = Profile.decode(encoded)

    assert decoded.product == :techtree
    assert decoded.principal_type == :agent
    assert decoded.wallet_address == "0xabc0000000000000000000000000000000000001"
  end

  test "group appData stores member profiles by product principal" do
    assert {:ok, app_data} =
             GroupAppData.encode(%{
               product: :platform,
               room_key: "company:animata",
               room_profile: %{name: "Animata Company Room"}
             })

    assert {:ok, updated} =
             GroupAppData.put_member_profile(app_data, "human-1", %{display_name: "Sean"})

    assert {:ok, profile} = GroupAppData.get_member_profile(updated, "human-1")
    assert profile["display_name"] == "Sean"
  end
end

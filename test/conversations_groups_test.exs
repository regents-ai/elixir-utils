defmodule XmtpElixirSdk.ConversationsGroupsTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias XmtpElixirSdk.Conversations
  alias XmtpElixirSdk.Groups
  alias XmtpElixirSdk.Types

  setup :start_runtime

  test "create and list groups and dms" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, _carol} = create_client("carol")
    assert {:ok, group} = create_group(alice, ["bob"], %Types.CreateGroupOptions{name: "Orbit"})
    assert {:ok, dm} = create_dm(alice, "carol")

    assert {:ok, groups} = Conversations.list_groups(alice)
    assert {:ok, dms} = Conversations.list_dms(alice)

    assert [group.id] == Enum.map(groups, & &1.id)
    assert [dm.id] == Enum.map(dms, & &1.id)
  end

  test "fetch dm by identifier and by inbox id" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, bob} = create_client("bob")
    assert {:ok, dm} = create_dm(alice, "bob")

    assert {:ok, by_id} = Conversations.fetch_dm_by_identifier(alice, identifier("bob"))
    assert {:ok, by_inbox} = Conversations.get_dm_by_inbox_id(alice, bob.inbox_id)

    assert by_id.id == dm.id
    assert by_inbox.id == dm.id
  end

  test "group metadata and membership changes return fresh conversations" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])

    assert {:ok, renamed} = Groups.update_name(group, "Fresh Name")
    assert {:ok, described} = Groups.update_description(renamed, "New Description")
    assert {:ok, with_member} = Groups.add_members(described, ["inbox-extra"])

    assert renamed.name == "Fresh Name"
    assert described.description == "New Description"
    assert Enum.any?(with_member.members, &(&1.inbox_id == "inbox-extra"))
  end

  test "admin and permission updates are reflected immediately" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])

    assert {:ok, promoted} = Groups.add_admin(group, bob.inbox_id)
    assert {:ok, true} = Groups.is_admin(promoted, bob.inbox_id)

    assert {:ok, locked} = Groups.update_permission(promoted, :update_metadata, :admin_only, :group_name)
    assert locked.permissions.policies.update_group_name == :admin_only
  end

  test "disappearing settings and removal flow stay on the conversation" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])

    assert {:ok, with_disappearing} =
             Groups.update_message_disappearing_settings(group, 10, 20)

    assert {:ok, true} = Groups.is_message_disappearing_enabled(with_disappearing)

    assert {:ok, pending} = Groups.request_removal(with_disappearing)
    assert {:ok, true} = Groups.is_pending_removal(pending)

    assert {:ok, cleared} = Groups.remove_message_disappearing_settings(pending)
    assert {:ok, false} = Groups.is_message_disappearing_enabled(cleared)
  end
end

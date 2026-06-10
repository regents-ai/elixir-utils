defmodule XmtpElixirSdk.ConversationsGroupsTest do
  use ExUnit.Case, async: false

  import XmtpElixirSdk.TestSupport

  alias XmtpElixirSdk.Conversations
  alias XmtpElixirSdk.Groups
  alias XmtpElixirSdk.Messages
  alias XmtpElixirSdk.Internal.Names
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
    assert {:ok, bob_group} = Conversations.get_by_id(bob, group.id)

    assert {:ok, locked} =
             Groups.update_permission(bob_group, :update_metadata, :admin_only, :group_name)

    assert locked.permissions.policies.update_group_name == :admin_only
  end

  test "admins cannot relax super-admin-only governance" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, bob} = create_client("bob")
    assert {:ok, carol} = create_client("carol")
    assert {:ok, group} = create_group(alice, ["bob", "carol"])
    assert {:ok, _promoted} = Groups.add_admin(group, bob.inbox_id)
    assert {:ok, bob_group} = Conversations.get_by_id(bob, group.id)

    assert {:error, error} = Groups.update_permission(bob_group, :add_admin, :allow)
    assert error.kind == :conflict
    assert error.message == "permission denied"

    assert {:error, add_error} = Groups.add_admin(bob_group, carol.inbox_id)
    assert add_error.kind == :conflict
    assert add_error.message == "permission denied"

    assert {:ok, refreshed} = refresh_conversation(group)
    assert refreshed.permissions.policies.add_admin == :super_admin_only
    assert {:ok, false} = Groups.is_admin(refreshed, carol.inbox_id)
  end

  test "regular members cannot update group permissions" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])
    assert {:ok, bob_group} = Conversations.get_by_id(bob, group.id)

    assert {:error, error} =
             Groups.update_permission(bob_group, :update_metadata, :admin_only, :group_name)

    assert error.kind == :conflict
    assert error.message == "permission denied"

    assert {:ok, refreshed} = refresh_conversation(group)
    assert refreshed.permissions.policies.update_group_name == :allow
  end

  test "unsupported permission updates are rejected" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])

    assert {:error, error} =
             Groups.update_permission(group, :update_metadata, :admin_only, :pinned_frame_url)

    assert error.kind == :invalid_argument
    assert error.message == "unsupported permission update"

    assert {:ok, refreshed} = refresh_conversation(group)
    refute Map.has_key?(refreshed.permissions.policies, :update_group_pinned_frame_url)
  end

  test "unsafe streamed terms are rejected cleanly" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])

    assert {:error, error} =
             Messages.process_streamed_message(group, :erlang.term_to_binary(make_ref()))

    assert error.kind == :invalid_argument
    assert error.message == "invalid streamed envelope"
  end

  test "unknown message content types do not create atoms during filtering" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])
    assert {:ok, message_id} = Messages.send_text(group, "hello")
    assert {:ok, %Types.Message{} = message} = Messages.get_by_id(alice, message_id)

    assert {:ok, [_message]} =
             Messages.list(group, %Types.ListMessagesOptions{content_types: [:text]})

    type_id = "releaseAuditUnknown#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(type_id) end

    :sys.replace_state(Names.conversation_server(alice), fn state ->
      unknown_content_type = %{message.content_type | type_id: type_id}
      unknown_message = %{message | content_type: unknown_content_type}
      conversation = state.conversations[group.id]

      messages =
        Enum.map(conversation.messages, fn stored_message ->
          if stored_message.id == message_id, do: unknown_message, else: stored_message
        end)

      updated_conversation = %{conversation | messages: messages}

      %{
        state
        | conversations: Map.put(state.conversations, group.id, updated_conversation),
          message_index: Map.put(state.message_index, message_id, unknown_message)
      }
    end)

    atom_count_before = :erlang.system_info(:atom_count)

    assert {:ok, []} =
             Messages.list(group, %Types.ListMessagesOptions{content_types: [:text]})

    atom_count_after = :erlang.system_info(:atom_count)
    assert atom_count_after == atom_count_before
    assert_raise ArgumentError, fn -> String.to_existing_atom(type_id) end
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

  test "expired messages are never listed across repeated reads" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])

    # from_ns: 0, in_ns: 1 => every message expires one nanosecond after it is
    # sent, so by the time we list it must already be pruned.
    assert {:ok, expiring_group} = Groups.update_message_disappearing_settings(group, 0, 1)

    assert {:ok, _id} = Messages.send_text(expiring_group, "vanishing")

    # The amortized fast path must not let an already-expired text message leak,
    # and repeated reads must stay consistent. (Group-update system messages are
    # exempt from expiry, so we only assert on disappearing text content.)
    refute_listed_text(expiring_group, "vanishing")
    refute_listed_text(expiring_group, "vanishing")
    assert {:ok, count} = Messages.count(expiring_group)
    assert is_integer(count)

    # A non-expiring conversation still returns its messages across reads.
    assert {:ok, keep_group} = create_group(alice, ["bob"])
    assert {:ok, _id} = Messages.send_text(keep_group, "stays")
    assert listed_text?(keep_group, "stays")
    assert listed_text?(keep_group, "stays")
  end

  defp refute_listed_text(conversation, text), do: refute(listed_text?(conversation, text))

  defp listed_text?(conversation, text) do
    assert {:ok, messages} = Messages.list(conversation)
    Enum.any?(messages, &match?(%{content: %{text: ^text}}, &1))
  end
end

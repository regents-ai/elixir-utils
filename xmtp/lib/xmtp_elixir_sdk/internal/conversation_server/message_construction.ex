defmodule XmtpElixirSdk.Internal.ConversationServer.MessageConstruction do
  @moduledoc false

  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Types

  alias XmtpElixirSdk.Types.{
    Conversation,
    ConversationMetadata,
    GroupMember,
    HmacKey,
    HmacKeyEntry,
    LastReadTime,
    Message
  }

  def dm_key(a, b), do: [a, b] |> Enum.sort() |> Enum.join(":")

  def build_message(client, conversation, content, message_id, sent_at_ns, delivery_status) do
    %Message{
      id: message_id,
      conversation_id: conversation.id,
      sender_inbox_id: client.inbox_id,
      sent_at_ns: sent_at_ns,
      delivery_status: delivery_status,
      kind: message_kind_for_content(content),
      content_type: Content.content_type_id(content),
      content: content,
      fallback: Content.fallback_for(content),
      num_replies: 0,
      reactions: [],
      expires_at_ns: expiry_for_conversation(conversation, sent_at_ns, content)
    }
  end

  def build_dm_conversation(client, conversation_id, peer_inbox, opts) do
    members = [
      %GroupMember{
        inbox_id: client.inbox_id,
        account_identifiers: [client.identifier.identifier],
        installation_ids: [client.installation_id],
        permission_level: :member,
        consent_state: :allowed
      },
      %GroupMember{
        inbox_id: peer_inbox,
        account_identifiers: [peer_inbox],
        installation_ids: [],
        permission_level: :member,
        consent_state: :unknown
      }
    ]

    initial_message =
      build_group_update_message(
        client,
        conversation_id,
        [
          %GroupMember{
            inbox_id: peer_inbox,
            account_identifiers: [peer_inbox],
            installation_ids: [],
            permission_level: :member,
            consent_state: :unknown
          }
        ],
        [],
        []
      )

    %Conversation{
      id: conversation_id,
      conversation_type: :dm,
      created_at_ns: System.system_time(:nanosecond),
      metadata: %ConversationMetadata{creator_inbox_id: client.inbox_id, conversation_type: :dm},
      added_by_inbox_id: client.inbox_id,
      name: "",
      image_url: "",
      description: "",
      app_data: "",
      permissions: Types.default_permissions(),
      consent_state: :allowed,
      disappearing_settings: Map.get(opts, :disappearing),
      paused_for_version: nil,
      pending_removal: false,
      last_activity_ns: System.system_time(:nanosecond),
      members: members,
      admins: [],
      super_admins: [],
      hmac_keys: [build_hmac_entry(conversation_id)],
      last_read_times: [%LastReadTime{inbox_id: client.inbox_id, timestamp_ns: 0}],
      messages: [initial_message]
    }
  end

  def build_group_conversation(client, conversation_id, members, opts) do
    group_members =
      Enum.map(members, fn inbox_id ->
        %GroupMember{
          inbox_id: inbox_id,
          account_identifiers: [inbox_id],
          installation_ids: [],
          permission_level: if(inbox_id == client.inbox_id, do: :admin, else: :member),
          consent_state: if(inbox_id == client.inbox_id, do: :allowed, else: :unknown)
        }
      end)

    admins =
      group_members |> Enum.filter(&(&1.permission_level == :admin)) |> Enum.map(& &1.inbox_id)

    super_admins =
      if Enum.any?(group_members, &(&1.inbox_id == client.inbox_id)),
        do: [client.inbox_id],
        else: []

    added_inboxes = Enum.reject(group_members, &(&1.inbox_id == client.inbox_id))

    permissions =
      Types.permission_policies_for_preset(
        Map.get(opts, :permissions, :all_members),
        Map.get(opts, :custom_permission_policy_set)
      )

    initial_message = build_group_update_message(client, conversation_id, added_inboxes, [], [])

    %Conversation{
      id: conversation_id,
      conversation_type: :group,
      created_at_ns: System.system_time(:nanosecond),
      metadata: %ConversationMetadata{
        creator_inbox_id: client.inbox_id,
        conversation_type: :group
      },
      added_by_inbox_id: client.inbox_id,
      name: Map.get(opts, :name, "") || "",
      image_url: Map.get(opts, :image_url, "") || "",
      description: Map.get(opts, :description, "") || "",
      app_data: Map.get(opts, :app_data, "") || "",
      permissions: %Types.Permissions{
        preset: Map.get(opts, :permissions, :all_members),
        policies: permissions
      },
      consent_state: :allowed,
      disappearing_settings: Map.get(opts, :disappearing),
      paused_for_version: nil,
      pending_removal: false,
      last_activity_ns: System.system_time(:nanosecond),
      members: group_members,
      admins: admins,
      super_admins: super_admins,
      hmac_keys: [build_hmac_entry(conversation_id)],
      last_read_times:
        Enum.map(group_members, &%LastReadTime{inbox_id: &1.inbox_id, timestamp_ns: 0}),
      messages: [initial_message]
    }
  end

  def build_group_update_message(
        %{inbox_id: inbox_id},
        conversation_id,
        added_inboxes,
        removed_inboxes,
        metadata_field_changes
      ) do
    content = %Content.GroupUpdated{
      metadata_field_changes: metadata_field_changes,
      added_inboxes: added_inboxes,
      removed_inboxes: removed_inboxes
    }

    %Message{
      id: "message-#{System.unique_integer([:positive])}",
      conversation_id: conversation_id,
      sender_inbox_id: inbox_id,
      sent_at_ns: System.system_time(:nanosecond),
      delivery_status: :published,
      kind: :membership_change,
      content_type: Content.content_type_id(content),
      content: content,
      fallback: Content.fallback_for(content),
      num_replies: 0,
      reactions: [],
      expires_at_ns: nil
    }
  end

  def build_group_update_message(
        %Conversation{} = conversation,
        added_inboxes,
        removed_inboxes,
        metadata_field_changes
      ) do
    build_group_update_message(
      %{inbox_id: conversation.added_by_inbox_id || conversation.metadata.creator_inbox_id},
      conversation.id,
      added_inboxes,
      removed_inboxes,
      metadata_field_changes
    )
  end

  def build_group_update_message_for_field(conversation, client, field, old_value, new_value) do
    change = %Types.MetadataFieldChange{
      field_name: Types.metadata_field_name(field),
      old_value: stringify_metadata_value(old_value),
      new_value: stringify_metadata_value(new_value)
    }

    build_group_update_message(client, conversation.id, [], [], [change])
  end

  def expired?(message, now_ns) do
    case effective_expiry(message) do
      nil -> false
      expires_at_ns -> now_ns >= expires_at_ns
    end
  end

  @doc """
  Returns the timestamp at which a message becomes expired, or `nil` when it
  can never expire.

  Mirrors `expired?/2`: `groupUpdated` messages and messages without an expiry
  never disappear. Callers use this to track the earliest upcoming expiry
  without re-encoding the exemption rules.
  """
  def effective_expiry(%Message{expires_at_ns: nil}), do: nil

  def effective_expiry(%Message{content_type: %Types.ContentTypeId{type_id: "groupUpdated"}}),
    do: nil

  def effective_expiry(%Message{expires_at_ns: expires_at_ns}), do: expires_at_ns

  defp build_hmac_entry(group_id) do
    %HmacKeyEntry{
      group_id: group_id,
      keys: [%HmacKey{key: :crypto.hash(:sha256, group_id), epoch: 0}]
    }
  end

  defp message_kind_for_content(%Content.GroupUpdated{}), do: :membership_change
  defp message_kind_for_content(_), do: :application

  defp expiry_for_conversation(
         %Conversation{
           disappearing_settings: %Types.DisappearingSettings{from_ns: from_ns, in_ns: in_ns}
         },
         sent_at_ns,
         _content
       )
       when in_ns > 0 do
    if sent_at_ns >= from_ns, do: sent_at_ns + in_ns, else: nil
  end

  defp expiry_for_conversation(_conversation, _sent_at_ns, _content), do: nil

  defp stringify_metadata_value(nil), do: ""
  defp stringify_metadata_value(value) when is_binary(value), do: value
  defp stringify_metadata_value(value), do: inspect(value)
end

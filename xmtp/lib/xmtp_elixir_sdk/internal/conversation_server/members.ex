defmodule XmtpElixirSdk.Internal.ConversationServer.Members do
  @moduledoc "Member, admin, and permission-policy mutations for conversation server state."

  alias XmtpElixirSdk.Internal.ConversationServer.Conversations
  alias XmtpElixirSdk.Internal.ConversationServer.MessageConstruction
  alias XmtpElixirSdk.Internal.ConversationServer.Messaging
  alias XmtpElixirSdk.Internal.ConversationServer.Permissions
  alias XmtpElixirSdk.Types.GroupMember

  def list(state, conversation_id) do
    case Conversations.fetch(state, conversation_id) do
      {:ok, conversation} -> {:ok, conversation.members}
      {:error, error} -> {:error, error}
    end
  end

  def admins(state, conversation_id),
    do: Conversations.fetch_field(state, conversation_id, :admins)

  def super_admins(state, conversation_id),
    do: Conversations.fetch_field(state, conversation_id, :super_admins)

  def admin?(state, conversation_id, inbox_id),
    do: field_contains?(state, conversation_id, :admins, inbox_id)

  def super_admin?(state, conversation_id, inbox_id),
    do: field_contains?(state, conversation_id, :super_admins, inbox_id)

  def mutate_members(state, client, conversation_id, inbox_ids, op) do
    with {:ok, conversation} <- Conversations.fetch(state, conversation_id),
         :ok <- Permissions.ensure(client, conversation, op, nil) do
      {members, added_inboxes, removed_inboxes} =
        case op do
          :add ->
            new_members =
              Enum.map(inbox_ids, fn inbox_id ->
                %GroupMember{
                  inbox_id: inbox_id,
                  account_identifiers: [inbox_id],
                  installation_ids: [],
                  permission_level: :member,
                  consent_state: :unknown
                }
              end)

            {Enum.uniq_by(conversation.members ++ new_members, & &1.inbox_id), new_members, []}

          :remove ->
            removed = Enum.filter(conversation.members, &(&1.inbox_id in inbox_ids))
            remaining = Enum.reject(conversation.members, &(&1.inbox_id in inbox_ids))
            {remaining, [], removed}
        end

      updated =
        %{conversation | members: members, last_activity_ns: System.system_time(:nanosecond)}
        |> Permissions.update_admin_lists_after_member_change()

      next_state = put_in(state.conversations[conversation_id], updated)

      next_state =
        Messaging.append_system_message(
          next_state,
          client.id,
          conversation_id,
          MessageConstruction.build_group_update_message(
            updated,
            added_inboxes,
            removed_inboxes,
            []
          )
        )

      next_state = Conversations.emit_updated(next_state, client.id, updated)
      {{:ok, updated}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  def mutate_admin(state, client, conversation_id, inbox_id, op) do
    with {:ok, conversation} <- Conversations.fetch(state, conversation_id),
         :ok <- Permissions.ensure(client, conversation, op, nil) do
      {admins, super_admins} =
        case op do
          :add_admin ->
            {Enum.uniq([inbox_id | conversation.admins]), conversation.super_admins}

          :remove_admin ->
            {Enum.reject(conversation.admins, &(&1 == inbox_id)), conversation.super_admins}

          :add_super_admin ->
            {conversation.admins, Enum.uniq([inbox_id | conversation.super_admins])}

          :remove_super_admin ->
            {conversation.admins, Enum.reject(conversation.super_admins, &(&1 == inbox_id))}
        end

      updated =
        %{
          conversation
          | admins: admins,
            super_admins: super_admins,
            last_activity_ns: System.system_time(:nanosecond)
        }
        |> Permissions.update_admin_lists_after_member_change()

      next_state =
        put_in(state.conversations[conversation_id], updated)
        |> Conversations.emit_updated(client.id, updated)

      {{:ok, updated}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  def update_permission(state, client, conversation_id, update_type, policy, metadata_field) do
    case Conversations.fetch(state, conversation_id) do
      {:ok, conversation} ->
        with {:ok, policy_field} <- Permissions.policy_field(update_type, metadata_field),
             :ok <- Permissions.validate_policy(policy),
             :ok <- Permissions.ensure(client, conversation, :manage_permissions, policy_field) do
          policies =
            Permissions.put_policy(conversation.permissions.policies, policy_field, policy)

          updated = %{
            conversation
            | permissions: %{conversation.permissions | policies: policies}
          }

          next_state =
            put_in(state.conversations[conversation_id], updated)
            |> Conversations.emit_updated(client.id, updated)

          {{:ok, updated}, next_state}
        else
          {:error, error} -> {{:error, error}, state}
        end

      {:error, error} ->
        {{:error, error}, state}
    end
  end

  defp field_contains?(state, conversation_id, field, value) do
    case Conversations.fetch(state, conversation_id) do
      {:ok, conversation} -> {:ok, value in Map.get(conversation, field)}
      {:error, error} -> {:error, error}
    end
  end
end

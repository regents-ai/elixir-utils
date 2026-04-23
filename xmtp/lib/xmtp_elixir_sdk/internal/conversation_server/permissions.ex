defmodule XmtpElixirSdk.Internal.ConversationServer.Permissions do
  @moduledoc false

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types.Conversation

  def ensure(_client, _conversation, nil, _metadata_field), do: :ok

  def ensure(client, conversation, action, metadata_field) do
    role =
      cond do
        client.inbox_id in conversation.super_admins -> :super_admin
        client.inbox_id in conversation.admins -> :admin
        true -> :member
      end

    with {:ok, policy} <- policy_for_action(conversation, action, metadata_field) do
      if allows?(policy, role) do
        :ok
      else
        {:error,
         Error.conflict("permission denied", %{
           action: action,
           metadata_field: metadata_field,
           inbox_id: client.inbox_id
         })}
      end
    end
  end

  def action_for_field(:name), do: :update_metadata
  def action_for_field(:description), do: :update_metadata
  def action_for_field(:image_url), do: :update_metadata
  def action_for_field(:app_data), do: :update_metadata
  def action_for_field(:disappearing_settings), do: :update_metadata
  def action_for_field(:pending_removal), do: nil
  def action_for_field(_), do: nil

  def metadata_field_for_update(:name), do: :group_name
  def metadata_field_for_update(:description), do: :description
  def metadata_field_for_update(:image_url), do: :image_url
  def metadata_field_for_update(:app_data), do: :app_data
  def metadata_field_for_update(:disappearing_settings), do: :message_disappearing
  def metadata_field_for_update(_), do: nil

  def put_policy(policies, policy_field, policy), do: Map.put(policies, policy_field, policy)

  def validate_policy(policy) when policy in [:allow, :deny, :admin_only, :super_admin_only],
    do: :ok

  def validate_policy(policy) do
    {:error, Error.invalid_argument("unsupported permission policy", %{policy: policy})}
  end

  def policy_field(:add_member, nil), do: {:ok, :add_member}
  def policy_field(:remove_member, nil), do: {:ok, :remove_member}
  def policy_field(:add_admin, nil), do: {:ok, :add_admin}
  def policy_field(:remove_admin, nil), do: {:ok, :remove_admin}
  def policy_field(:update_metadata, :group_name), do: {:ok, :update_group_name}
  def policy_field(:update_metadata, :description), do: {:ok, :update_group_description}
  def policy_field(:update_metadata, :image_url), do: {:ok, :update_group_image_url}

  def policy_field(:update_metadata, :message_disappearing),
    do: {:ok, :update_message_disappearing}

  def policy_field(:update_metadata, :app_data), do: {:ok, :update_app_data}

  def policy_field(update_type, metadata_field) do
    {:error,
     Error.invalid_argument("unsupported permission update", %{
       update_type: update_type,
       metadata_field: metadata_field
     })}
  end

  def update_admin_lists_after_member_change(%Conversation{} = conversation) do
    member_ids = Enum.map(conversation.members, & &1.inbox_id)
    admins = Enum.filter(conversation.admins, &(&1 in member_ids))
    super_admins = Enum.filter(conversation.super_admins, &(&1 in member_ids))

    members =
      Enum.map(conversation.members, fn member ->
        permission_level =
          cond do
            member.inbox_id in super_admins -> :super_admin
            member.inbox_id in admins -> :admin
            true -> :member
          end

        %{member | permission_level: permission_level}
      end)

    %{conversation | members: members, admins: admins, super_admins: super_admins}
  end

  defp allows?(:allow, _role), do: true
  defp allows?(:deny, _role), do: false
  defp allows?(:admin_only, role), do: role in [:admin, :super_admin]
  defp allows?(:super_admin_only, role), do: role == :super_admin
  defp allows?(_policy, _role), do: true

  defp policy_for_action(conversation, :add, _metadata_field),
    do: {:ok, conversation.permissions.policies.add_member}

  defp policy_for_action(conversation, :remove, _metadata_field),
    do: {:ok, conversation.permissions.policies.remove_member}

  defp policy_for_action(conversation, :add_admin, _metadata_field),
    do: {:ok, conversation.permissions.policies.add_admin}

  defp policy_for_action(conversation, :remove_admin, _metadata_field),
    do: {:ok, conversation.permissions.policies.remove_admin}

  defp policy_for_action(conversation, :add_super_admin, _metadata_field),
    do: {:ok, conversation.permissions.policies.add_admin}

  defp policy_for_action(conversation, :remove_super_admin, _metadata_field),
    do: {:ok, conversation.permissions.policies.remove_admin}

  defp policy_for_action(conversation, :manage_permissions, policy_field) do
    conversation.permissions.policies
    |> Map.fetch!(policy_field)
    |> policy_for_permission_edit()
    |> then(&{:ok, &1})
  end

  defp policy_for_action(conversation, :update_metadata, :group_name),
    do: {:ok, conversation.permissions.policies.update_group_name}

  defp policy_for_action(conversation, :update_metadata, :description),
    do: {:ok, conversation.permissions.policies.update_group_description}

  defp policy_for_action(conversation, :update_metadata, :image_url),
    do: {:ok, conversation.permissions.policies.update_group_image_url}

  defp policy_for_action(conversation, :update_metadata, :app_data),
    do: {:ok, conversation.permissions.policies.update_app_data}

  defp policy_for_action(conversation, :update_metadata, :message_disappearing),
    do: {:ok, conversation.permissions.policies.update_message_disappearing}

  defp policy_for_action(_conversation, action, metadata_field) do
    {:error,
     Error.invalid_argument("unsupported permission action", %{
       action: action,
       metadata_field: metadata_field
     })}
  end

  defp policy_for_permission_edit(:super_admin_only), do: :super_admin_only
  defp policy_for_permission_edit(_policy), do: :admin_only
end

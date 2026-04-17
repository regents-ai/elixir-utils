defmodule XmtpElixirSdk.Groups do
  @moduledoc """
  Group membership, roles, permissions, and metadata.

  Use this module once you already have a group conversation and need to manage
  it.

  Common tasks:

  - change group name, image, description, or app data
  - inspect or update group permissions
  - add or remove members
  - promote or demote admins and super admins
  - inspect group debug information and timestamps
  """

  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Internal.ConversationServer
  alias XmtpElixirSdk.Internal.IdentityServer
  alias XmtpElixirSdk.Types

  @spec sync(Conversation.t()) :: {:ok, Conversation.t()} | {:error, Error.t()}
  def sync(%Conversation{client: client, id: id}) do
    ConversationServer.conversation_sync(client, id)
    |> case do
      {:ok, updated} -> {:ok, Conversation.from_record(client, updated)}
      other -> other
    end
  end

  @spec update_name(Conversation.t(), String.t()) :: {:ok, Conversation.t()} | {:error, Error.t()}
  def update_name(%Conversation{client: client, id: id}, name) do
    update(client, id, :name, name)
  end

  @spec update_image_url(Conversation.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def update_image_url(%Conversation{client: client, id: id}, image_url) do
    update(client, id, :image_url, image_url)
  end

  @spec update_description(Conversation.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def update_description(%Conversation{client: client, id: id}, description) do
    update(client, id, :description, description)
  end

  @spec update_app_data(Conversation.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def update_app_data(%Conversation{client: client, id: id}, app_data) do
    update(client, id, :app_data, app_data)
  end

  @spec permissions(Conversation.t()) :: {:ok, Types.Permissions.t()} | {:error, Error.t()}
  def permissions(%Conversation{permissions: permissions}), do: {:ok, permissions || Types.default_permissions()}

  @spec update_permission(Conversation.t(), atom(), atom(), Types.metadata_field() | nil) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def update_permission(%Conversation{client: client, id: id}, update_type, policy, metadata_field \\ nil) do
    with {:ok, updated} <- ConversationServer.update_permission(client, id, update_type, policy, metadata_field) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec list_admins(Conversation.t()) :: {:ok, [String.t()]} | {:error, Error.t()}
  def list_admins(%Conversation{client: client, id: id}), do: ConversationServer.list_admins(client, id)

  @spec list_super_admins(Conversation.t()) :: {:ok, [String.t()]} | {:error, Error.t()}
  def list_super_admins(%Conversation{client: client, id: id}), do: ConversationServer.list_super_admins(client, id)

  @spec is_admin(Conversation.t(), String.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def is_admin(%Conversation{client: client, id: id}, inbox_id), do: ConversationServer.is_admin(client, id, inbox_id)

  @spec is_super_admin(Conversation.t(), String.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def is_super_admin(%Conversation{client: client, id: id}, inbox_id), do: ConversationServer.is_super_admin(client, id, inbox_id)

  @spec add_members_by_identifiers(Conversation.t(), [Types.Identifier.t()]) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def add_members_by_identifiers(%Conversation{client: client} = conversation, identifiers) do
    with {:ok, inbox_ids} <- resolve_inbox_ids(client, identifiers) do
      add_members(conversation, inbox_ids)
    end
  end

  @spec add_members(Conversation.t(), [String.t()]) :: {:ok, Conversation.t()} | {:error, Error.t()}
  def add_members(%Conversation{client: client, id: id}, inbox_ids) do
    with {:ok, updated} <- ConversationServer.add_members(client, id, inbox_ids) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec remove_members_by_identifiers(Conversation.t(), [Types.Identifier.t()]) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def remove_members_by_identifiers(%Conversation{client: client} = conversation, identifiers) do
    with {:ok, inbox_ids} <- resolve_inbox_ids(client, identifiers) do
      remove_members(conversation, inbox_ids)
    end
  end

  @spec remove_members(Conversation.t(), [String.t()]) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def remove_members(%Conversation{client: client, id: id}, inbox_ids) do
    with {:ok, updated} <- ConversationServer.remove_members(client, id, inbox_ids) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec add_admin(Conversation.t(), String.t()) :: {:ok, Conversation.t()} | {:error, Error.t()}
  def add_admin(%Conversation{client: client, id: id}, inbox_id) do
    with {:ok, updated} <- ConversationServer.add_admin(client, id, inbox_id) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec remove_admin(Conversation.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def remove_admin(%Conversation{client: client, id: id}, inbox_id) do
    with {:ok, updated} <- ConversationServer.remove_admin(client, id, inbox_id) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec add_super_admin(Conversation.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def add_super_admin(%Conversation{client: client, id: id}, inbox_id) do
    with {:ok, updated} <- ConversationServer.add_super_admin(client, id, inbox_id) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec remove_super_admin(Conversation.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def remove_super_admin(%Conversation{client: client, id: id}, inbox_id) do
    with {:ok, updated} <- ConversationServer.remove_super_admin(client, id, inbox_id) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec request_removal(Conversation.t()) :: {:ok, Conversation.t()} | {:error, Error.t()}
  def request_removal(%Conversation{client: client, id: id}) do
    with {:ok, updated} <- ConversationServer.request_removal(client, id) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec is_pending_removal(Conversation.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def is_pending_removal(%Conversation{client: client, id: id}), do: ConversationServer.is_pending_removal(client, id)

  @spec message_disappearing_settings(Conversation.t()) ::
          {:ok, Types.DisappearingSettings.t() | nil} | {:error, Error.t()}
  def message_disappearing_settings(%Conversation{client: client, id: id}) do
    ConversationServer.conversation_disappearing_settings(client, id)
  end

  @spec update_message_disappearing_settings(Conversation.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def update_message_disappearing_settings(%Conversation{client: client, id: id}, from_ns, in_ns) do
    with {:ok, updated} <- ConversationServer.update_disappearing_settings(client, id, %Types.DisappearingSettings{from_ns: from_ns, in_ns: in_ns}) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec remove_message_disappearing_settings(Conversation.t()) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def remove_message_disappearing_settings(%Conversation{client: client, id: id}) do
    with {:ok, updated} <- ConversationServer.remove_disappearing_settings(client, id) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  @spec is_message_disappearing_enabled(Conversation.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def is_message_disappearing_enabled(%Conversation{client: client, id: id}) do
    ConversationServer.is_disappearing_enabled(client, id)
  end

  @spec paused_for_version(Conversation.t()) :: {:ok, String.t() | nil} | {:error, Error.t()}
  def paused_for_version(%Conversation{client: client, id: id}), do: ConversationServer.paused_for_version(client, id)

  @spec hmac_keys(Conversation.t()) :: {:ok, [Types.HmacKeyEntry.t()]} | {:error, Error.t()}
  def hmac_keys(%Conversation{client: client, id: id}), do: ConversationServer.hmac_keys(client, id)

  @spec debug_info(Conversation.t()) :: {:ok, Types.ConversationDebugInfo.t()} | {:error, Error.t()}
  def debug_info(%Conversation{client: client, id: id}), do: ConversationServer.conversation_debug_info(client, id)

  @spec last_read_times(Conversation.t()) :: {:ok, [Types.LastReadTime.t()]} | {:error, Error.t()}
  def last_read_times(%Conversation{client: client, id: id}), do: ConversationServer.last_read_times(client, id)

  defp update(client, id, field, value) do
    with {:ok, updated} <- ConversationServer.update_conversation_field(client, id, field, value) do
      {:ok, Conversation.from_record(client, updated)}
    end
  end

  defp resolve_inbox_ids(client, identifiers) do
    identifiers
    |> Enum.reduce_while({:ok, []}, fn identifier, {:ok, acc} ->
      case IdentityServer.get_inbox_id_for_identifier(client.runtime, identifier) do
        {:ok, inbox_id} -> {:cont, {:ok, [inbox_id | acc]}}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, inbox_ids} -> {:ok, Enum.reverse(inbox_ids)}
      {:error, error} -> {:error, error}
    end
  end
end

defmodule XmtpElixirSdk.Conversation do
  @moduledoc """
  Plain XMTP conversation data.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Date, as: XmtpDate
  alias XmtpElixirSdk.Types

  defstruct [
    :runtime,
    :client,
    :id,
    :created_at_ns,
    :metadata,
    :added_by_inbox_id,
    :conversation_type,
    :name,
    :description,
    :image_url,
    :app_data,
    :permissions,
    :consent_state,
    :disappearing_settings,
    :paused_for_version,
    :pending_removal,
    :last_activity_ns,
    :members,
    :admins,
    :super_admins,
    :hmac_keys,
    :last_read_times
  ]

  @type t :: %__MODULE__{
          runtime: atom(),
          client: Client.t(),
          id: String.t(),
          created_at_ns: non_neg_integer() | nil,
          metadata: Types.ConversationMetadata.t() | nil,
          added_by_inbox_id: String.t() | nil,
          conversation_type: Types.conversation_type() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          image_url: String.t() | nil,
          app_data: String.t() | nil,
          permissions: Types.Permissions.t() | nil,
          consent_state: Types.consent_state() | nil,
          disappearing_settings: Types.DisappearingSettings.t() | nil,
          paused_for_version: String.t() | nil,
          pending_removal: boolean() | nil,
          last_activity_ns: non_neg_integer() | nil,
          members: [Types.GroupMember.t()] | nil,
          admins: [String.t()] | nil,
          super_admins: [String.t()] | nil,
          hmac_keys: [Types.HmacKeyEntry.t()] | nil,
          last_read_times: [Types.LastReadTime.t()] | nil
        }

  @spec from_record(Client.t(), Types.Conversation.t()) :: t()
  def from_record(%Client{} = client, conversation) do
    %__MODULE__{
      runtime: client.runtime,
      client: client,
      id: conversation.id,
      created_at_ns: conversation.created_at_ns,
      metadata: conversation.metadata,
      added_by_inbox_id: conversation.added_by_inbox_id,
      conversation_type: conversation.conversation_type,
      name: conversation.name,
      description: conversation.description,
      image_url: conversation.image_url,
      app_data: conversation.app_data,
      permissions: conversation.permissions,
      consent_state: Map.get(conversation, :consent_state),
      disappearing_settings: Map.get(conversation, :disappearing_settings),
      paused_for_version: Map.get(conversation, :paused_for_version),
      pending_removal: Map.get(conversation, :pending_removal),
      last_activity_ns: Map.get(conversation, :last_activity_ns),
      members: Map.get(conversation, :members, []),
      admins: Map.get(conversation, :admins, []),
      super_admins: Map.get(conversation, :super_admins, []),
      hmac_keys: Map.get(conversation, :hmac_keys, []),
      last_read_times: Map.get(conversation, :last_read_times, [])
    }
  end

  @spec created_at(t()) :: DateTime.t() | nil
  def created_at(%__MODULE__{created_at_ns: nil}), do: nil

  def created_at(%__MODULE__{created_at_ns: created_at_ns}),
    do: XmtpDate.ns_to_datetime(created_at_ns)

  @spec topic(t()) :: String.t()
  def topic(%__MODULE__{id: id}), do: "/xmtp/mls/1/g-#{id}/proto"
end

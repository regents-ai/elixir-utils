defmodule XmtpElixirSdk.Types do
  @moduledoc """
  Core SDK value objects and enum helpers.
  """

  alias XmtpElixirSdk.Error

  @metadata_field_names %{
    group_name: "group_name",
    description: "description",
    image_url: "group_image_url_square",
    pinned_frame_url: "group_pinned_frame_url",
    app_data: "app_data",
    message_disappearing: "message_disappearing"
  }
  @metadata_fields_by_name Map.new(@metadata_field_names, fn {field, name} -> {name, field} end)

  @type env :: :local | :dev | :production | :testnet_staging | :testnet_dev | :testnet | :mainnet
  @type identifier_kind :: :ethereum | :passkey
  @type conversation_type :: :dm | :group | :sync | :oneshot
  @type consent_state :: :unknown | :allowed | :denied
  @type consent_entity_type :: :group_id | :inbox_id
  @type message_kind :: :application | :membership_change
  @type delivery_status :: :unpublished | :published | :failed
  @type permission_level :: :member | :admin | :super_admin
  @type group_permissions_preset :: :all_members | :admin_only | :custom
  @type permission_policy ::
          :allow | :deny | :admin_only | :super_admin_only | :does_not_exist | :other
  @type sort_direction :: :ascending | :descending
  @type metadata_field ::
          :group_name
          | :description
          | :image_url
          | :pinned_frame_url
          | :app_data
          | :message_disappearing
  @type preference_kind :: :consent | :hmac_key
  @type consent_record ::
          %{required(:entity) => String.t(), required(:state) => consent_state()}
          | %{required(:group_id) => String.t(), required(:state) => consent_state()}

  @spec env_url(env()) :: String.t()
  def env_url(:local), do: "http://localhost:5556"
  def env_url(:dev), do: "https://grpc.dev.xmtp.network:443"
  def env_url(:production), do: "https://grpc.production.xmtp.network:443"
  def env_url(:testnet_staging), do: "https://grpc.testnet-staging.xmtp.network:443"
  def env_url(:testnet_dev), do: "https://grpc.testnet-dev.xmtp.network:443"
  def env_url(:testnet), do: "https://grpc.testnet.xmtp.network:443"
  def env_url(:mainnet), do: "https://grpc.mainnet.xmtp.network:443"

  @spec secure_env?(env()) :: boolean()
  def secure_env?(:local), do: false
  def secure_env?(_), do: true

  @spec api_url(env()) :: String.t()
  def api_url(:local), do: "http://localhost:5557"
  def api_url(:dev), do: "https://api.dev.xmtp.network:5558"
  def api_url(:production), do: "https://api.production.xmtp.network:5558"
  def api_url(env), do: env_url(env)

  @spec history_sync_url(env()) :: String.t()
  def history_sync_url(:local), do: "http://localhost:5558"
  def history_sync_url(:dev), do: "https://message-history.dev.ephemera.network"
  def history_sync_url(:production), do: "https://message-history.production.ephemera.network"
  def history_sync_url(:testnet_staging), do: "https://message-history.dev.ephemera.network"
  def history_sync_url(:testnet_dev), do: "https://message-history.dev.ephemera.network"
  def history_sync_url(:testnet), do: "https://message-history.dev.ephemera.network"
  def history_sync_url(:mainnet), do: "https://message-history.production.ephemera.network"

  defmodule Identifier do
    @moduledoc "Account identifier."
    @enforce_keys [:identifier, :identifier_kind]
    defstruct [:identifier, :identifier_kind]

    @type t :: %__MODULE__{
            identifier: String.t(),
            identifier_kind: XmtpElixirSdk.Types.identifier_kind()
          }
  end

  defmodule ContentTypeId do
    @moduledoc "Content type identifier."
    @enforce_keys [:authority_id, :type_id, :version_major, :version_minor]
    defstruct [:authority_id, :type_id, :version_major, :version_minor]

    @type t :: %__MODULE__{
            authority_id: String.t(),
            type_id: String.t(),
            version_major: non_neg_integer(),
            version_minor: non_neg_integer()
          }
  end

  defmodule SendOptions do
    @moduledoc "Message send options."
    defstruct should_push: true
    @type t :: %__MODULE__{should_push: boolean()}
  end

  defmodule DisappearingSettings do
    @moduledoc "Message disappearing settings."
    defstruct from_ns: 0, in_ns: 0
    @type t :: %__MODULE__{from_ns: non_neg_integer(), in_ns: non_neg_integer()}
  end

  defmodule ConsentUpdate do
    @moduledoc "Consent update from a preference stream."
    defstruct [:entity_type, :state, :entity]

    @type t :: %__MODULE__{
            entity_type: XmtpElixirSdk.Types.consent_entity_type(),
            state: XmtpElixirSdk.Types.consent_state(),
            entity: String.t()
          }
  end

  defmodule PreferenceUpdate do
    @moduledoc "Preference update from a preference stream."
    defstruct [:kind, :consent]

    @type t :: %__MODULE__{
            kind: XmtpElixirSdk.Types.preference_kind(),
            consent: ConsentUpdate.t() | nil
          }
  end

  defmodule PermissionPolicySet do
    @moduledoc "Per-action permission policies."
    defstruct [
      :add_member,
      :remove_member,
      :add_admin,
      :remove_admin,
      :update_group_name,
      :update_group_description,
      :update_group_image_url,
      :update_message_disappearing,
      :update_app_data
    ]

    @type t :: %__MODULE__{
            add_member: XmtpElixirSdk.Types.permission_policy(),
            remove_member: XmtpElixirSdk.Types.permission_policy(),
            add_admin: XmtpElixirSdk.Types.permission_policy(),
            remove_admin: XmtpElixirSdk.Types.permission_policy(),
            update_group_name: XmtpElixirSdk.Types.permission_policy(),
            update_group_description: XmtpElixirSdk.Types.permission_policy(),
            update_group_image_url: XmtpElixirSdk.Types.permission_policy(),
            update_message_disappearing: XmtpElixirSdk.Types.permission_policy(),
            update_app_data: XmtpElixirSdk.Types.permission_policy()
          }
  end

  defmodule Permissions do
    @moduledoc "Conversation permissions."
    defstruct [:preset, :policies]

    @type t :: %__MODULE__{
            preset: XmtpElixirSdk.Types.group_permissions_preset(),
            policies: PermissionPolicySet.t()
          }
  end

  defmodule ConversationMetadata do
    @moduledoc "Conversation metadata."
    defstruct [:creator_inbox_id, :conversation_type]

    @type t :: %__MODULE__{
            creator_inbox_id: String.t(),
            conversation_type: XmtpElixirSdk.Types.conversation_type()
          }
  end

  defmodule GroupMember do
    @moduledoc "Group member snapshot."
    defstruct [
      :inbox_id,
      :permission_level,
      account_identifiers: [],
      installation_ids: [],
      consent_state: :unknown
    ]

    @type t :: %__MODULE__{
            inbox_id: String.t(),
            account_identifiers: [String.t()],
            installation_ids: [String.t()],
            permission_level: XmtpElixirSdk.Types.permission_level(),
            consent_state: XmtpElixirSdk.Types.consent_state()
          }
  end

  defmodule Cursor do
    @moduledoc "Conversation cursor."
    defstruct [:originator_id, :sequence_id]
    @type t :: %__MODULE__{originator_id: non_neg_integer(), sequence_id: non_neg_integer()}
  end

  defmodule HmacKey do
    @moduledoc "HMAC key material."
    defstruct [:key, :epoch]
    @type t :: %__MODULE__{key: binary(), epoch: integer()}
  end

  defmodule HmacKeyEntry do
    @moduledoc "Conversation HMAC key entry."
    defstruct [:group_id, keys: []]
    @type t :: %__MODULE__{group_id: String.t(), keys: [HmacKey.t()]}
  end

  defmodule LastReadTime do
    @moduledoc "Per-inbox last-read timestamp."
    defstruct [:inbox_id, :timestamp_ns]
    @type t :: %__MODULE__{inbox_id: String.t(), timestamp_ns: non_neg_integer()}
  end

  defmodule ConversationDebugInfo do
    @moduledoc "Conversation debug data."
    defstruct [
      :epoch,
      :maybe_forked,
      :fork_details,
      :is_commit_log_forked,
      :local_commit_log,
      :remote_commit_log,
      cursor: []
    ]

    @type t :: %__MODULE__{
            epoch: non_neg_integer(),
            maybe_forked: boolean(),
            fork_details: String.t() | nil,
            is_commit_log_forked: boolean() | nil,
            local_commit_log: String.t() | nil,
            remote_commit_log: String.t() | nil,
            cursor: [Cursor.t()]
          }
  end

  defmodule ApiStats do
    @moduledoc "API call statistics."
    defstruct [
      :upload_key_package,
      :fetch_key_package,
      :send_group_messages,
      :send_welcome_messages,
      :query_group_messages,
      :query_welcome_messages,
      :subscribe_messages,
      :subscribe_welcomes,
      :publish_commit_log,
      :query_commit_log,
      :get_newest_group_message
    ]

    @type t :: %__MODULE__{}
  end

  defmodule IdentityStats do
    @moduledoc "Identity call statistics."
    defstruct [
      :publish_identity_update,
      :get_identity_updates_v2,
      :get_inbox_ids,
      :verify_smart_contract_wallet_signature
    ]

    @type t :: %__MODULE__{}
  end

  defmodule KeyPackageStatus do
    @moduledoc "Key package status."
    defstruct [:installation_id, :valid, :not_before, :not_after, :validation_error]

    @type t :: %__MODULE__{
            installation_id: String.t(),
            valid: boolean(),
            not_before: non_neg_integer(),
            not_after: non_neg_integer(),
            validation_error: String.t() | nil
          }
  end

  defmodule SyncResult do
    @moduledoc "Sync result."
    defstruct [:synced, :eligible]
    @type t :: %__MODULE__{synced: non_neg_integer(), eligible: non_neg_integer()}
  end

  defmodule Installation do
    @moduledoc "Installation snapshot."
    defstruct [:id, :bytes]
    @type t :: %__MODULE__{id: String.t(), bytes: binary()}
  end

  defmodule InboxState do
    @moduledoc "Inbox state snapshot."
    defstruct [
      :inbox_id,
      :recovery_identifier,
      :identifiers,
      :installation_ids,
      :account_identifiers,
      :installations
    ]

    @type t :: %__MODULE__{
            inbox_id: String.t(),
            recovery_identifier: String.t(),
            identifiers: [String.t()],
            installation_ids: [String.t()],
            account_identifiers: [Identifier.t()],
            installations: [Installation.t()]
          }
  end

  defmodule CreateGroupOptions do
    @moduledoc "Group creation options."
    defstruct [
      :permissions,
      :custom_permission_policy_set,
      :name,
      :description,
      :image_url,
      :app_data,
      :disappearing
    ]

    @type t :: %__MODULE__{
            permissions: XmtpElixirSdk.Types.group_permissions_preset() | nil,
            custom_permission_policy_set: PermissionPolicySet.t() | nil,
            name: String.t() | nil,
            description: String.t() | nil,
            image_url: String.t() | nil,
            app_data: String.t() | nil,
            disappearing: DisappearingSettings.t() | nil
          }
  end

  defmodule CreateDmOptions do
    @moduledoc "DM creation options."
    defstruct disappearing: nil
    @type t :: %__MODULE__{disappearing: DisappearingSettings.t() | nil}
  end

  defmodule ListMessagesOptions do
    @moduledoc "Message listing options."
    defstruct sent_after_ns: 0,
              sent_before_ns: 0,
              limit: 100,
              direction: :ascending,
              delivery_status: nil,
              kind: nil,
              content_types: []

    @type t :: %__MODULE__{
            sent_after_ns: integer(),
            sent_before_ns: integer(),
            limit: non_neg_integer(),
            direction: XmtpElixirSdk.Types.sort_direction() | nil,
            delivery_status: XmtpElixirSdk.Types.delivery_status() | nil,
            kind: XmtpElixirSdk.Types.message_kind() | nil,
            content_types: [atom()]
          }
  end

  defmodule ListConversationsOptions do
    @moduledoc "Conversation listing options."
    defstruct [
      :conversation_type,
      limit: 100,
      created_after_ns: 0,
      created_before_ns: 0,
      last_activity_after_ns: 0,
      last_activity_before_ns: 0,
      consent_states: [],
      order_by: :created_at,
      include_duplicate_dms: false
    ]

    @type t :: %__MODULE__{
            conversation_type: XmtpElixirSdk.Types.conversation_type() | nil,
            limit: non_neg_integer(),
            created_after_ns: integer(),
            created_before_ns: integer(),
            last_activity_after_ns: integer(),
            last_activity_before_ns: integer(),
            consent_states: [XmtpElixirSdk.Types.consent_state()],
            order_by: :created_at | :last_activity,
            include_duplicate_dms: boolean()
          }
  end

  defmodule Message do
    @moduledoc "Stored message."
    defstruct [
      :id,
      :conversation_id,
      :sender_inbox_id,
      :sent_at_ns,
      :delivery_status,
      :kind,
      :content_type,
      :content,
      :fallback,
      :num_replies,
      reactions: [],
      expires_at_ns: nil
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            conversation_id: String.t(),
            sender_inbox_id: String.t(),
            sent_at_ns: non_neg_integer(),
            delivery_status: XmtpElixirSdk.Types.delivery_status(),
            kind: XmtpElixirSdk.Types.message_kind(),
            content_type: ContentTypeId.t(),
            content: term(),
            fallback: String.t() | nil,
            num_replies: non_neg_integer(),
            reactions: [t()],
            expires_at_ns: non_neg_integer() | nil
          }
  end

  defmodule MetadataFieldChange do
    @moduledoc "Conversation metadata field change."
    defstruct [:field_name, :old_value, :new_value]
    @type t :: %__MODULE__{field_name: String.t(), old_value: String.t(), new_value: String.t()}
  end

  defmodule GroupUpdated do
    @moduledoc "Group update content."
    defstruct metadata_field_changes: [], added_inboxes: [], removed_inboxes: []

    @type t :: %__MODULE__{
            metadata_field_changes: [MetadataFieldChange.t()],
            added_inboxes: [GroupMember.t()],
            removed_inboxes: [GroupMember.t()]
          }
  end

  defmodule Action do
    @moduledoc "Single action option."
    defstruct [:id, :label, :style]
    @type t :: %__MODULE__{id: String.t(), label: String.t(), style: atom() | nil}
  end

  defmodule Actions do
    @moduledoc "Action list content."
    defstruct [:id, :description, actions: []]
    @type t :: %__MODULE__{id: String.t(), description: String.t(), actions: [Action.t()]}
  end

  defmodule Intent do
    @moduledoc "Intent content."
    defstruct [:id, :action_id]
    @type t :: %__MODULE__{id: String.t(), action_id: String.t()}
  end

  defmodule TransactionReference do
    @moduledoc "Transaction reference content."
    defstruct [:namespace, :network_id, :reference, :metadata]

    @type t :: %__MODULE__{
            namespace: String.t() | nil,
            network_id: String.t(),
            reference: String.t(),
            metadata: map() | nil
          }
  end

  defmodule WalletCall do
    @moduledoc "Wallet call."
    defstruct [:to, :data, :value, :metadata]

    @type t :: %__MODULE__{
            to: String.t(),
            data: String.t(),
            value: String.t(),
            metadata: map() | nil
          }
  end

  defmodule WalletSendCalls do
    @moduledoc "Wallet send calls content."
    defstruct [:version, :chain_id, :from, calls: [], capabilities: nil]

    @type t :: %__MODULE__{
            version: String.t(),
            chain_id: String.t(),
            from: String.t(),
            calls: [WalletCall.t()],
            capabilities: map() | nil
          }
  end

  defmodule MultiRemoteAttachment do
    @moduledoc "Multiple remote attachments."
    defstruct attachments: []
    @type t :: %__MODULE__{attachments: [map()]}
  end

  defmodule ArchiveOptions do
    @moduledoc "Archive options."
    defstruct elements: [], exclude_disappearing_messages: false
    @type t :: %__MODULE__{elements: [atom()], exclude_disappearing_messages: boolean()}
  end

  defmodule ArchiveMetadata do
    @moduledoc "Archive metadata."
    defstruct [:pin, :server_url, :created_at_ns, :item_count, :options]

    @type t :: %__MODULE__{
            pin: String.t(),
            server_url: String.t(),
            created_at_ns: non_neg_integer(),
            item_count: non_neg_integer(),
            options: ArchiveOptions.t()
          }
  end

  defmodule AvailableArchiveInfo do
    @moduledoc "Available archive info."
    defstruct [:pin, :server_url, :created_at_ns, :item_count]

    @type t :: %__MODULE__{
            pin: String.t(),
            server_url: String.t(),
            created_at_ns: non_neg_integer(),
            item_count: non_neg_integer()
          }
  end

  defmodule GroupSyncSummary do
    @moduledoc "Device sync summary."
    defstruct [:synced, :eligible]
    @type t :: %__MODULE__{synced: non_neg_integer(), eligible: non_neg_integer()}
  end

  defmodule Conversation do
    @moduledoc "Conversation snapshot."
    defstruct [
      :id,
      :conversation_type,
      :created_at_ns,
      :metadata,
      :added_by_inbox_id,
      :name,
      :image_url,
      :description,
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
      :last_read_times,
      :messages
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            conversation_type: XmtpElixirSdk.Types.conversation_type(),
            created_at_ns: non_neg_integer(),
            metadata: ConversationMetadata.t(),
            added_by_inbox_id: String.t(),
            name: String.t(),
            image_url: String.t(),
            description: String.t(),
            app_data: String.t(),
            permissions: Permissions.t(),
            consent_state: XmtpElixirSdk.Types.consent_state(),
            disappearing_settings: DisappearingSettings.t() | nil,
            paused_for_version: String.t() | nil,
            pending_removal: boolean(),
            last_activity_ns: non_neg_integer(),
            members: [GroupMember.t()],
            admins: [String.t()],
            super_admins: [String.t()],
            hmac_keys: [HmacKeyEntry.t()],
            last_read_times: [LastReadTime.t()],
            messages: [Message.t()]
          }
  end

  @spec default_permission_policies() :: PermissionPolicySet.t()
  def default_permission_policies do
    %PermissionPolicySet{
      add_member: :allow,
      remove_member: :admin_only,
      add_admin: :super_admin_only,
      remove_admin: :super_admin_only,
      update_group_name: :allow,
      update_group_description: :allow,
      update_group_image_url: :allow,
      update_message_disappearing: :admin_only,
      update_app_data: :allow
    }
  end

  @spec permission_policies_for_preset(group_permissions_preset(), PermissionPolicySet.t() | nil) ::
          PermissionPolicySet.t()
  def permission_policies_for_preset(nil, _custom), do: default_permission_policies()
  def permission_policies_for_preset(:all_members, _custom), do: default_permission_policies()

  def permission_policies_for_preset(:admin_only, _custom) do
    %PermissionPolicySet{
      add_member: :admin_only,
      remove_member: :admin_only,
      add_admin: :super_admin_only,
      remove_admin: :super_admin_only,
      update_group_name: :admin_only,
      update_group_description: :admin_only,
      update_group_image_url: :admin_only,
      update_message_disappearing: :admin_only,
      update_app_data: :admin_only
    }
  end

  def permission_policies_for_preset(:custom, %PermissionPolicySet{} = custom), do: custom
  def permission_policies_for_preset(:custom, _custom), do: default_permission_policies()

  @spec default_permissions() :: Permissions.t()
  def default_permissions do
    %Permissions{preset: :all_members, policies: default_permission_policies()}
  end

  @spec empty_debug_info() :: ConversationDebugInfo.t()
  def empty_debug_info do
    %ConversationDebugInfo{
      epoch: 0,
      maybe_forked: false,
      fork_details: nil,
      is_commit_log_forked: nil,
      local_commit_log: nil,
      remote_commit_log: nil,
      cursor: []
    }
  end

  @spec metadata_field_name(metadata_field()) :: String.t()
  def metadata_field_name(field), do: Map.fetch!(@metadata_field_names, field)

  @spec metadata_field_from_name(String.t()) :: {:ok, metadata_field()} | {:error, Error.t()}
  def metadata_field_from_name(name) do
    case Map.fetch(@metadata_fields_by_name, name) do
      {:ok, field} ->
        {:ok, field}

      :error ->
        {:error, Error.invalid_argument("unknown metadata field", %{field: name})}
    end
  end
end

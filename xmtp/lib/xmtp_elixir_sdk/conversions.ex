defmodule XmtpElixirSdk.Conversions do
  @moduledoc """
  Public conversion helpers for stable SDK-facing shapes.
  """

  alias XmtpElixirSdk.Types

  @safe_conversation_fields [
    :id,
    :name,
    :image_url,
    :description,
    :app_data,
    :permissions,
    :added_by_inbox_id,
    :metadata,
    :admins,
    :super_admins,
    :created_at_ns
  ]

  defmodule SafeConversation do
    @moduledoc "Stable conversation shape for public utility helpers."
    defstruct [
      :id,
      :name,
      :image_url,
      :description,
      :app_data,
      :permissions,
      :added_by_inbox_id,
      :metadata,
      :admins,
      :super_admins,
      :created_at_ns
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            image_url: String.t(),
            description: String.t(),
            app_data: String.t(),
            permissions: Types.Permissions.t(),
            added_by_inbox_id: String.t(),
            metadata: Types.ConversationMetadata.t(),
            admins: [String.t()],
            super_admins: [String.t()],
            created_at_ns: non_neg_integer()
          }
  end

  @spec to_safe_conversation(Types.Conversation.t()) :: SafeConversation.t()
  def to_safe_conversation(%Types.Conversation{} = conversation) do
    struct(SafeConversation, Map.take(conversation, @safe_conversation_fields))
  end

  @spec hmac_keys_map([Types.HmacKeyEntry.t()]) :: %{optional(String.t()) => [Types.HmacKey.t()]}
  def hmac_keys_map(entries), do: Map.new(entries, &{&1.group_id, &1.keys})

  @spec last_read_times_map([Types.LastReadTime.t()]) :: %{
          optional(String.t()) => non_neg_integer()
        }
  def last_read_times_map(entries), do: Map.new(entries, &{&1.inbox_id, &1.timestamp_ns})
end

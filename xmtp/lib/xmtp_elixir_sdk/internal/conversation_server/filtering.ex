defmodule XmtpElixirSdk.Internal.ConversationServer.Filtering do
  @moduledoc false

  alias XmtpElixirSdk.Types
  alias XmtpElixirSdk.Types.Message

  def member_of?(conversation, inbox_id),
    do: Enum.any?(conversation.members, &(&1.inbox_id == inbox_id))

  def filter_conversations(conversations, opts) do
    Enum.filter(conversations, fn conversation ->
      type_ok? =
        is_nil(opts.conversation_type) or conversation.conversation_type == opts.conversation_type

      consent_ok? =
        Enum.empty?(opts.consent_states) or conversation.consent_state in opts.consent_states

      created_after_ok? =
        opts.created_after_ns == 0 or conversation.created_at_ns > opts.created_after_ns

      created_before_ok? =
        opts.created_before_ns == 0 or conversation.created_at_ns < opts.created_before_ns

      last_activity_after_ok? =
        opts.last_activity_after_ns == 0 or
          conversation.last_activity_ns > opts.last_activity_after_ns

      last_activity_before_ok? =
        opts.last_activity_before_ns == 0 or
          conversation.last_activity_ns < opts.last_activity_before_ns

      type_ok? and consent_ok? and created_after_ok? and created_before_ok? and
        last_activity_after_ok? and last_activity_before_ok?
    end)
  end

  def sort_conversations(conversations, opts) do
    case opts.order_by do
      :last_activity -> Enum.sort_by(conversations, & &1.last_activity_ns, :desc)
      _ -> Enum.sort_by(conversations, & &1.created_at_ns, :desc)
    end
  end

  def filter_messages(messages, opts) do
    Enum.filter(messages, fn message ->
      delivery_ok? =
        is_nil(opts.delivery_status) or message.delivery_status == opts.delivery_status

      kind_ok? = is_nil(opts.kind) or message.kind == opts.kind

      content_types_ok? =
        Enum.empty?(opts.content_types) or
          content_type_filter_key(message.content_type) in opts.content_types

      delivery_ok? and kind_ok? and content_types_ok?
    end)
  end

  def within_message_window?(message, opts) do
    after_ok? = opts.sent_after_ns == 0 or message.sent_at_ns >= opts.sent_after_ns
    before_ok? = opts.sent_before_ns == 0 or message.sent_at_ns <= opts.sent_before_ns
    after_ok? and before_ok?
  end

  def sort_messages(messages, opts) do
    case opts.direction do
      :descending -> Enum.sort_by(messages, & &1.sent_at_ns, :desc)
      _ -> Enum.sort_by(messages, & &1.sent_at_ns, :asc)
    end
  end

  def visible_message?(%Message{delivery_status: :unpublished, sender_inbox_id: sender}, client),
    do: sender == client.inbox_id

  def visible_message?(%Message{}, _client), do: true

  def countable_message?(%Message{kind: :application}), do: true
  def countable_message?(%Message{}), do: false

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "text"}), do: :text
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "markdown"}), do: :markdown
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "reaction"}), do: :reaction
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "reply"}), do: :reply
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "readReceipt"}), do: :read_receipt
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "attachment"}), do: :attachment

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "remoteStaticAttachment"}),
    do: :remote_attachment

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "groupUpdated"}), do: :group_updated
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "actions"}), do: :actions
  defp content_type_filter_key(%Types.ContentTypeId{type_id: "intent"}), do: :intent

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "transactionReference"}),
    do: :transaction_reference

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "walletSendCalls"}),
    do: :wallet_send_calls

  defp content_type_filter_key(%Types.ContentTypeId{type_id: "multiRemoteAttachment"}),
    do: :multi_remote_attachment

  defp content_type_filter_key(%Types.ContentTypeId{type_id: type_id}), do: {:unknown, type_id}
end

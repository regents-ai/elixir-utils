defmodule XmtpElixirSdk.DecodedMessage do
  @moduledoc """
  Message surface with custom content decoded through a codec registry.
  """

  alias XmtpElixirSdk.CodecRegistry
  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Date, as: XmtpDate
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types

  defstruct [
    :id,
    :conversation_id,
    :sender_inbox_id,
    :sent_at_ns,
    :sent_at,
    :delivery_status,
    :kind,
    :content_type,
    :content,
    :fallback,
    :num_replies,
    :decode_status,
    :decode_error,
    reactions: [],
    expires_at_ns: nil,
    expires_at: nil
  ]

  @type decode_status :: :decoded | :unknown | :failed

  @type t :: %__MODULE__{
          id: String.t(),
          conversation_id: String.t(),
          sender_inbox_id: String.t(),
          sent_at_ns: non_neg_integer(),
          sent_at: DateTime.t(),
          delivery_status: Types.delivery_status(),
          kind: Types.message_kind(),
          content_type: Types.ContentTypeId.t(),
          content: term(),
          fallback: String.t() | nil,
          num_replies: non_neg_integer(),
          reactions: [t()],
          expires_at_ns: non_neg_integer() | nil,
          expires_at: DateTime.t() | nil,
          decode_status: decode_status(),
          decode_error: Error.t() | nil
        }

  @spec from_message(Types.Message.t(), CodecRegistry.t()) :: t()
  def from_message(%Types.Message{} = message, registry \\ CodecRegistry.new()) do
    reactions = Enum.map(message.reactions, &from_message(&1, registry))
    {content, decode_status, decode_error} = decode_content(message.content, registry)

    %__MODULE__{
      id: message.id,
      conversation_id: message.conversation_id,
      sender_inbox_id: message.sender_inbox_id,
      sent_at_ns: message.sent_at_ns,
      sent_at: XmtpDate.ns_to_datetime(message.sent_at_ns),
      delivery_status: message.delivery_status,
      kind: message.kind,
      content_type: message.content_type,
      content: content,
      fallback: message.fallback,
      num_replies: message.num_replies,
      reactions: reactions,
      expires_at_ns: message.expires_at_ns,
      expires_at: decode_expires_at(message.expires_at_ns),
      decode_status: decode_status,
      decode_error: decode_error
    }
  end

  @spec decoded?(t()) :: boolean()
  def decoded?(%__MODULE__{decode_status: :decoded}), do: true
  def decoded?(%__MODULE__{}), do: false

  @spec unknown?(t()) :: boolean()
  def unknown?(%__MODULE__{decode_status: :unknown}), do: true
  def unknown?(%__MODULE__{}), do: false

  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{decode_status: :failed}), do: true
  def failed?(%__MODULE__{}), do: false

  @spec reaction?(t()) :: boolean()
  def reaction?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "reaction"}
      }),
      do: true

  def reaction?(%__MODULE__{}), do: false

  @spec reply?(t()) :: boolean()
  def reply?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "reply"}
      }),
      do: true

  def reply?(%__MODULE__{}), do: false

  @spec text_reply?(t()) :: boolean()
  def text_reply?(%__MODULE__{} = message) do
    reply?(message) and match?(%Content.Reply{content: %Content.Text{}}, message.content)
  end

  @spec text?(t()) :: boolean()
  def text?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "text"}
      }),
      do: true

  def text?(%__MODULE__{}), do: false

  @spec markdown?(t()) :: boolean()
  def markdown?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "markdown"}
      }),
      do: true

  def markdown?(%__MODULE__{}), do: false

  @spec attachment?(t()) :: boolean()
  def attachment?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "attachment"}
      }),
      do: true

  def attachment?(%__MODULE__{}), do: false

  @spec remote_attachment?(t()) :: boolean()
  def remote_attachment?(%__MODULE__{
        content_type: %Types.ContentTypeId{
          authority_id: "xmtp.org",
          type_id: "remoteStaticAttachment"
        }
      }),
      do: true

  def remote_attachment?(%__MODULE__{}), do: false

  @spec multi_remote_attachment?(t()) :: boolean()
  def multi_remote_attachment?(%__MODULE__{
        content_type: %Types.ContentTypeId{
          authority_id: "xmtp.org",
          type_id: "multiRemoteAttachment"
        }
      }),
      do: true

  def multi_remote_attachment?(%__MODULE__{}), do: false

  @spec transaction_reference?(t()) :: boolean()
  def transaction_reference?(%__MODULE__{
        content_type: %Types.ContentTypeId{
          authority_id: "xmtp.org",
          type_id: "transactionReference"
        }
      }),
      do: true

  def transaction_reference?(%__MODULE__{}), do: false

  @spec group_updated?(t()) :: boolean()
  def group_updated?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "groupUpdated"}
      }),
      do: true

  def group_updated?(%__MODULE__{}), do: false

  @spec read_receipt?(t()) :: boolean()
  def read_receipt?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "readReceipt"}
      }),
      do: true

  def read_receipt?(%__MODULE__{}), do: false

  @spec wallet_send_calls?(t()) :: boolean()
  def wallet_send_calls?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "walletSendCalls"}
      }),
      do: true

  def wallet_send_calls?(%__MODULE__{}), do: false

  @spec intent?(t()) :: boolean()
  def intent?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "intent"}
      }),
      do: true

  def intent?(%__MODULE__{}), do: false

  @spec actions?(t()) :: boolean()
  def actions?(%__MODULE__{
        content_type: %Types.ContentTypeId{authority_id: "xmtp.org", type_id: "actions"}
      }),
      do: true

  def actions?(%__MODULE__{}), do: false

  @spec content_type(t()) :: Types.ContentTypeId.t()
  def content_type(%__MODULE__{content_type: content_type}), do: content_type

  @spec reply_content_type(t()) :: Types.ContentTypeId.t() | nil
  def reply_content_type(%__MODULE__{content: %Content.Reply{content_type: content_type}}),
    do: content_type

  def reply_content_type(%__MODULE__{}), do: nil

  @spec decode_content(term(), CodecRegistry.t()) :: {term(), decode_status(), Error.t() | nil}
  defp decode_content(%Content.Reply{} = reply, registry) do
    {inner_content, inner_status, inner_error} = decode_content(reply.content, registry)
    content_type = reply.content_type || infer_content_type(reply.content)

    decoded_reply =
      %Content.Reply{
        reply
        | content: inner_content,
          content_type: content_type,
          in_reply_to: decode_in_reply_to(reply.in_reply_to, registry)
      }

    {decoded_reply, inner_status, inner_error}
  end

  defp decode_content(%Content.Unknown{} = content, registry) do
    case CodecRegistry.decode(registry, content) do
      {:ok, decoded} ->
        {decoded, :decoded, nil}

      {:error, :missing_codec} ->
        {nil, :unknown, nil}

      {:error, %Error{} = error} ->
        {nil, :failed, error}
    end
  end

  defp decode_content(content, _registry), do: {content, :decoded, nil}

  @spec decode_in_reply_to(term(), CodecRegistry.t()) :: term()
  defp decode_in_reply_to(%Types.Message{} = message, registry),
    do: from_message(message, registry)

  defp decode_in_reply_to(other, _registry), do: other

  defp decode_expires_at(nil), do: nil
  defp decode_expires_at(expires_at_ns), do: XmtpDate.ns_to_datetime(expires_at_ns)

  defp infer_content_type(%Content.Unknown{} = content), do: Content.content_type_id(content)
  defp infer_content_type(content), do: Content.content_type_id(content)
end

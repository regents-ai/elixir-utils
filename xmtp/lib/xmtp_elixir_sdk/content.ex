defmodule XmtpElixirSdk.Content do
  @moduledoc """
  Core content helpers used by messages and conversations.
  """

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types.ContentTypeId

  defmodule Text do
    @moduledoc "Plain text content."
    defstruct [:text]
    @type t :: %__MODULE__{text: String.t()}
  end

  defmodule Markdown do
    @moduledoc "Markdown content."
    defstruct [:markdown]
    @type t :: %__MODULE__{markdown: String.t()}
  end

  defmodule Reaction do
    @moduledoc "Reaction content."
    defstruct [:reference, :reference_inbox_id, :action, :content, :schema]

    @type t :: %__MODULE__{
            reference: String.t(),
            reference_inbox_id: String.t(),
            action: :added | :removed,
            content: String.t(),
            schema: :unicode | :shortcode | :custom
          }
  end

  defmodule Reply do
    @moduledoc "Reply content."
    defstruct [:reference, :reference_inbox_id, :content, :content_type, :in_reply_to]

    @type t :: %__MODULE__{
            reference: String.t(),
            reference_inbox_id: String.t() | nil,
            content: term(),
            content_type: XmtpElixirSdk.Types.ContentTypeId.t() | nil,
            in_reply_to: term() | nil
          }
  end

  defmodule ReadReceipt do
    @moduledoc "Read receipt marker."
    defstruct []
    @type t :: %__MODULE__{}
  end

  defmodule Attachment do
    @moduledoc "Inline attachment."
    defstruct [:filename, :mime_type, :data]
    @type t :: %__MODULE__{filename: String.t() | nil, mime_type: String.t(), data: binary()}
  end

  defmodule RemoteAttachment do
    @moduledoc "Remote attachment."
    defstruct [
      :url,
      :content_digest,
      :secret,
      :nonce,
      :salt,
      :scheme,
      :content_length,
      :filename
    ]

    @type t :: %__MODULE__{
            url: String.t(),
            content_digest: String.t(),
            secret: binary(),
            nonce: binary(),
            salt: binary(),
            scheme: String.t(),
            content_length: non_neg_integer() | nil,
            filename: String.t() | nil
          }
  end

  defmodule GroupUpdated do
    @moduledoc "Group update content."
    defstruct metadata_field_changes: [], added_inboxes: [], removed_inboxes: []

    @type t :: %__MODULE__{
            metadata_field_changes: [map()],
            added_inboxes: [map()],
            removed_inboxes: [map()]
          }
  end

  defmodule Actions do
    @moduledoc "Action list content."
    defstruct [:id, :description, :expires_at_ns, actions: []]

    @type t :: %__MODULE__{
            id: String.t(),
            description: String.t(),
            expires_at_ns: non_neg_integer() | nil,
            actions: [map()]
          }
  end

  defmodule Intent do
    @moduledoc "Intent content."
    defstruct [:id, :action_id, :metadata]
    @type t :: %__MODULE__{id: String.t(), action_id: String.t(), metadata: map() | nil}
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

  defmodule Unknown do
    @moduledoc "Unknown content payload."
    defstruct [:content_type, :raw]
    @type t :: %__MODULE__{content_type: String.t(), raw: term()}
  end

  @type t ::
          Text.t()
          | Markdown.t()
          | Reaction.t()
          | Reply.t()
          | ReadReceipt.t()
          | Attachment.t()
          | RemoteAttachment.t()
          | GroupUpdated.t()
          | Actions.t()
          | Intent.t()
          | TransactionReference.t()
          | WalletSendCalls.t()
          | MultiRemoteAttachment.t()
          | Unknown.t()

  @spec content_type_id(t()) :: ContentTypeId.t()
  def content_type_id(%Text{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "text",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%Markdown{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "markdown",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%Reaction{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "reaction",
      version_major: 2,
      version_minor: 0
    }

  def content_type_id(%Reply{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "reply",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%ReadReceipt{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "readReceipt",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%Attachment{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "attachment",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%RemoteAttachment{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "remoteStaticAttachment",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%GroupUpdated{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "groupUpdated",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%Actions{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "actions",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%Intent{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "intent",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%TransactionReference{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "transactionReference",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%WalletSendCalls{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "walletSendCalls",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%MultiRemoteAttachment{}),
    do: %ContentTypeId{
      authority_id: "xmtp.org",
      type_id: "multiRemoteAttachment",
      version_major: 1,
      version_minor: 0
    }

  def content_type_id(%Unknown{content_type: content_type}) when is_binary(content_type) do
    case String.split(content_type, "/") do
      [authority, rest] ->
        case String.split(rest, ":") do
          [type, version] ->
            [major, minor] = String.split(version, ".")

            %ContentTypeId{
              authority_id: authority,
              type_id: type,
              version_major: String.to_integer(major),
              version_minor: String.to_integer(minor)
            }

          _ ->
            %ContentTypeId{
              authority_id: authority,
              type_id: rest,
              version_major: 0,
              version_minor: 0
            }
        end

      _ ->
        %ContentTypeId{
          authority_id: "unknown",
          type_id: content_type,
          version_major: 0,
          version_minor: 0
        }
    end
  end

  @spec content_type_to_string(ContentTypeId.t()) :: String.t()
  def content_type_to_string(%ContentTypeId{} = content_type) do
    "#{content_type.authority_id}/#{content_type.type_id}:#{content_type.version_major}.#{content_type.version_minor}"
  end

  @spec encode_text(String.t()) :: Text.t()
  def encode_text(text), do: %Text{text: text}

  @spec encode_markdown(String.t()) :: Markdown.t()
  def encode_markdown(markdown), do: %Markdown{markdown: markdown}

  @spec encode_reaction(String.t(), String.t(), :added | :removed) :: Reaction.t()
  def encode_reaction(reference, content, action) do
    %Reaction{
      reference: reference,
      reference_inbox_id: "",
      action: action,
      content: content,
      schema: :unicode
    }
  end

  @spec encode_read_receipt() :: ReadReceipt.t()
  def encode_read_receipt, do: %ReadReceipt{}

  @spec encode_reply(String.t(), term()) :: Reply.t()
  def encode_reply(reference, inner_content) do
    %Reply{
      reference: reference,
      reference_inbox_id: nil,
      content: inner_content,
      content_type: content_type_id(inner_content),
      in_reply_to: nil
    }
  end

  @spec encode_text_reply(String.t(), String.t()) :: Reply.t()
  def encode_text_reply(reference, text), do: encode_reply(reference, encode_text(text))

  @spec encode_attachment(Attachment.t()) :: Attachment.t()
  def encode_attachment(%Attachment{} = attachment), do: attachment

  @spec encode_remote_attachment(RemoteAttachment.t()) :: RemoteAttachment.t()
  def encode_remote_attachment(%RemoteAttachment{} = attachment), do: attachment

  @spec encode_group_updated(GroupUpdated.t()) :: GroupUpdated.t()
  def encode_group_updated(%GroupUpdated{} = content), do: content

  @spec encode_actions(Actions.t()) :: Actions.t()
  def encode_actions(%Actions{} = content), do: content

  @spec encode_intent(Intent.t()) :: Intent.t()
  def encode_intent(%Intent{} = content), do: content

  @spec encode_transaction_reference(TransactionReference.t()) :: TransactionReference.t()
  def encode_transaction_reference(%TransactionReference{} = content), do: content

  @spec encode_wallet_send_calls(WalletSendCalls.t()) :: WalletSendCalls.t()
  def encode_wallet_send_calls(%WalletSendCalls{} = content), do: content

  @spec encode_multi_remote_attachment(MultiRemoteAttachment.t()) :: MultiRemoteAttachment.t()
  def encode_multi_remote_attachment(%MultiRemoteAttachment{} = content), do: content

  @spec fallback_for(t()) :: String.t() | nil
  def fallback_for(%Text{}), do: nil
  def fallback_for(%Markdown{}), do: nil
  def fallback_for(%ReadReceipt{}), do: nil
  def fallback_for(%GroupUpdated{}), do: "Group updated"

  def fallback_for(%Reaction{action: action, content: content}) do
    case action do
      :removed -> "Removed \"#{content}\" from an earlier message"
      _ -> "Reacted with \"#{content}\" to an earlier message"
    end
  end

  def fallback_for(%Reply{content: %Text{text: text}}),
    do: "Replied with \"#{text}\" to an earlier message"

  def fallback_for(%Reply{}), do: "Replied to an earlier message"

  def fallback_for(%Attachment{filename: filename}) when is_binary(filename) and filename != "" do
    "Can't display #{filename}. This app doesn't support attachments."
  end

  def fallback_for(%Attachment{}),
    do: "Can't display this content. This app doesn't support attachments."

  def fallback_for(%RemoteAttachment{filename: filename})
      when is_binary(filename) and filename != "" do
    "Can't display #{filename}. This app doesn't support remote attachments."
  end

  def fallback_for(%RemoteAttachment{}),
    do: "Can't display this content. This app doesn't support remote attachments."

  def fallback_for(%MultiRemoteAttachment{}),
    do: "Can't display this content. This app doesn't support multiple remote attachments."

  def fallback_for(%TransactionReference{reference: ""}), do: "Crypto transaction"

  def fallback_for(%TransactionReference{reference: reference}),
    do:
      "[Crypto transaction] Use a blockchain explorer to learn more using the transaction hash: #{reference}"

  def fallback_for(%WalletSendCalls{}), do: "Wallet action request"

  def fallback_for(%Actions{description: description, actions: actions}) do
    action_lines =
      actions
      |> Enum.with_index(1)
      |> Enum.map(fn {action, index} -> "[#{index}] #{Map.get(action, :label, "")}" end)
      |> Enum.join("\n")

    Enum.join([description, action_lines, "Reply with the number to select"], "\n\n")
  end

  def fallback_for(%Intent{action_id: action_id}), do: "Intent: #{action_id}"
  def fallback_for(%Unknown{}), do: nil

  @spec decode(term()) :: {:ok, t()} | {:error, Error.t()}
  def decode(%Text{} = content), do: {:ok, content}
  def decode(%Markdown{} = content), do: {:ok, content}
  def decode(%Reaction{} = content), do: {:ok, content}
  def decode(%Reply{} = content), do: {:ok, content}
  def decode(%ReadReceipt{} = content), do: {:ok, content}
  def decode(%Attachment{} = content), do: {:ok, content}
  def decode(%RemoteAttachment{} = content), do: {:ok, content}
  def decode(%GroupUpdated{} = content), do: {:ok, content}
  def decode(%Actions{} = content), do: {:ok, content}
  def decode(%Intent{} = content), do: {:ok, content}
  def decode(%TransactionReference{} = content), do: {:ok, content}
  def decode(%WalletSendCalls{} = content), do: {:ok, content}
  def decode(%MultiRemoteAttachment{} = content), do: {:ok, content}
  def decode(%Unknown{} = content), do: {:ok, content}

  def decode(other),
    do: {:error, Error.invalid_argument("unsupported content", %{content: other})}
end
